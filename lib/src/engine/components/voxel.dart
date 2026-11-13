part of '../../engine.dart';

/// Component managing multi-chunk 3D voxel terrain, greedy meshing, and fast 3D DDA raycasting.
final class VoxelTerrainComponent extends Component {
  final vworld.VoxelWorld world;
  late final vworld.GreedyMesher _mesher;
  late final vworld.VoxelRaycaster _raycaster;
  double voxelScale;

  final Map<vworld.ChunkCoord, vworld.VoxelMesh> _cachedMeshes = {};

  VoxelTerrainComponent({vworld.VoxelWorld? world, this.voxelScale = 1.0})
    : world = world ?? vworld.VoxelWorld() {
    _mesher = vworld.GreedyMesher(this.world.palette);
    _raycaster = vworld.VoxelRaycaster(this.world);
  }

  /// Gets block ID at world voxel coordinate.
  int getVoxel(int wx, int wy, int wz) => world.getVoxel(wx, wy, wz);

  /// Sets block ID at world voxel coordinate and marks chunk dirty.
  void setVoxel(int wx, int wy, int wz, int blockId) {
    world.setVoxel(wx, wy, wz, blockId);
    final cc = world.worldToChunk(wx, wy, wz);
    _cachedMeshes.remove(cc);
  }

  /// Carves a spherical cavity out of the terrain at [center] with [radius].
  int carveSphere(
    vworld.VoxelCoord center,
    double radius, [
    int replaceWith = 0,
  ]) {
    final modified = vworld.VoxelBrush.sphereCarve(
      world,
      center: center,
      radius: radius,
      replaceWith: replaceWith,
    );
    if (modified > 0) {
      _cachedMeshes.clear();
    }
    return modified;
  }

  /// Fills an axis-aligned box with [blockId].
  int fillBox(vworld.VoxelCoord min, vworld.VoxelCoord max, int blockId) {
    final count = vworld.VoxelBrush.boxFill(
      world,
      min: min,
      max: max,
      blockId: blockId,
    );
    if (count > 0) {
      _cachedMeshes.clear();
    }
    return count;
  }

  /// Performs a fast 3D DDA raycast through the voxel terrain in local/world coordinate space.
  vworld.VoxelRaycastHit? raycastVoxel(
    Vec3 origin,
    Vec3 direction, {
    double maxDistance = 64.0,
  }) {
    // Transform ray into voxel local grid coordinates
    final rootPos = isAttached ? transform.position : Vec3.zero;
    final invScale = 1.0 / voxelScale;
    final diff = origin - rootPos;
    final localOrigin = Vec3(
      diff.x * invScale,
      diff.y * invScale,
      diff.z * invScale,
    );

    final vOrigin = vworld.VoxelVec3(
      localOrigin.x,
      localOrigin.y,
      localOrigin.z,
    );
    final vDir = vworld.VoxelVec3(direction.x, direction.y, direction.z);

    return _raycaster.raycast(
      origin: vOrigin,
      direction: vDir,
      maxDistance: maxDistance / voxelScale,
    );
  }

  /// Generates or returns the cached greedy mesh for a given chunk.
  vworld.VoxelMesh getChunkMesh(vworld.ChunkCoord coord) {
    return _cachedMeshes.putIfAbsent(
      coord,
      () => _mesher.meshWorldChunk(world, coord),
    );
  }

  /// Rebuilds greedy meshes for all non-empty chunks.
  Map<vworld.ChunkCoord, vworld.VoxelMesh> rebuildAllMeshes() {
    _cachedMeshes.clear();
    for (final chunk in world.chunks) {
      if (!chunk.isEmpty) {
        _cachedMeshes[chunk.coord] = _mesher.meshWorldChunk(world, chunk.coord);
      }
    }
    return Map.unmodifiable(_cachedMeshes);
  }
}
