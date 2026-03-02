# Use the multi-threaded image!
FROM --platform=linux/amd64 keenon/opencascade.js AS base

RUN apt-get update -y && apt-get install -y wget

# 3. Inject SIMD, C++17, and OCCGEOMETRY flags into compilation scripts
RUN sed -i 's/"-O3",/"-O3", "-std=c++17", "-DOCCGEOMETRY",/g' /opencascade.js/src/compileSources.py && \
    sed -i 's/"-O3",/"-O3", "-std=c++17", "-DOCCGEOMETRY",/g' /opencascade.js/src/compileBindings.py && \
    sed -i 's/"-O3",/"-O3", "-std=c++17", "-DOCCGEOMETRY",/g' /opencascade.js/src/buildFromYaml.py

# Clone and build Netgen
WORKDIR /netgen_src
RUN git clone https://github.com/NGSolve/netgen.git . && \
    git checkout v6.2.2601

RUN sed -i 's/ & anyflags//g' libsrc/core/flags.cpp

# 2. Force Netgen to use the legacy JS exception model (-fexceptions) 
# so it perfectly matches the OpenCascade.js pre-compiled objects.
# TODO: upgrade this to wasm-exceptions once we also upgrade the OpenCascade docker build
# RUN find . -type f -name "CMakeLists.txt" -o -name "*.cmake" | xargs sed -i 's/-fwasm-exceptions/-fexceptions/g'

# 3. Patch Netgen's CMakeLists.txt to bypass find_package(OpenCascade), ZLIB, and TKernel property checks
RUN sed -i 's/find_package(OpenCascade.*//g' CMakeLists.txt && \
    sed -i 's/target_link_libraries(occ_libs INTERFACE ${OCC_LIBRARIES})//g' CMakeLists.txt && \
    sed -i '/get_target_property(occ_include_dir TKernel/d' CMakeLists.txt && \
    sed -i '/ZLIB/d' CMakeLists.txt

# 4. Configure and Build Netgen libraries (STATIC only, skipping executables)
# Wrapped OCC_INC assignment in quotes to handle spaces correctly
WORKDIR /netgen_build
RUN OCC_INC="$(find /occt/src -type d | sed 's/^/-I/' | tr '\n' ' ')" && \
    emcmake cmake ../netgen_src \
    -DUSE_GUI=OFF \
    -DUSE_PYTHON=OFF \
    -DUSE_MPI=OFF \
    -DUSE_CSG=OFF \
    -DUSE_OCC=ON \
    -DUSE_SUPERBUILD=OFF \
    -DUSE_NATIVE_ARCH=OFF \
    -DNGLIB_LIBRARY_TYPE=STATIC \
    -DNGCORE_LIBRARY_TYPE=STATIC \
    -DOpenCASCADE_INCLUDE_DIR=/occt/src/ \
    -DCMAKE_CXX_FLAGS="-pthread -O3 -msimd128 -msse2 -DOCCGEOMETRY -s USE_ZLIB=1 $OCC_INC" \
    && emmake make nglib ngcore -j$(nproc)

# 11. Expose Netgen headers (Adding the nglib folder as well)
RUN echo '\nadditionalIncludePaths.append("/netgen_src/include")' >> /opencascade.js/src/Common.py && \
    echo '\nadditionalIncludePaths.append("/netgen_src/libsrc")' >> /opencascade.js/src/Common.py && \
    echo '\nadditionalIncludePaths.append("/netgen_src/libsrc/include")' >> /opencascade.js/src/Common.py && \
    echo '\nadditionalIncludePaths.append("/netgen_build")' >> /opencascade.js/src/Common.py && \
    echo '\nadditionalIncludePaths.append("/netgen_src/libsrc/meshing")' >> /opencascade.js/src/Common.py && \
    echo '\nadditionalIncludePaths.append("/netgen_src/libsrc/occ")' >> /opencascade.js/src/Common.py && \
    echo '\nadditionalIncludePaths.append("/netgen_src/nglib")' >> /opencascade.js/src/Common.py

# 12. Pre-build the LTO version of Zlib as root and open cache permissions
RUN echo "int main() {return 0;}" > /tmp/test.c && \
    emcc -flto -s USE_ZLIB=1 /tmp/test.c -o /tmp/test.js && \
    rm /tmp/test.* && \
    chmod -R 777 /emsdk/upstream/emscripten/cache

# 13. Combine all Netgen static libraries into a single archive for easy linking
RUN cd /netgen_build && \
    echo "create libnetgen_all.a" > script.mri && \
    find . -name "*.a" -exec echo "addlib {}" \; >> script.mri && \
    echo "save" >> script.mri && \
    echo "end" >> script.mri && \
    llvm-ar -M < script.mri