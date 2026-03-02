// ============================================================================
// Custom Netgen InterOp Types
// ============================================================================

export interface MeshData {
  vertices: Float64Array;
  tetrahedra: Int32Array;
}

export declare class Ng_Mesh {
  GetNP(): number;
  GetNE(): number;
  delete(): void;
}

export declare class NetgenInterOp {
  static GenerateTetMesh(shape: TopoDS_Shape, maxH: number): Ng_Mesh;
  static GetMeshData(mesh: Ng_Mesh): MeshData;
  delete(): void;
}

export type NetgenOpenCascadeInstance = OpenCascadeInstance & {
  NetgenInterOp: typeof NetgenInterOp;
  Ng_Mesh: typeof Ng_Mesh;
};