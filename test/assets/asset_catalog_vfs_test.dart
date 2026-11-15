import 'dart:convert';
import 'dart:typed_data';

import 'package:gl_volition/gl_volition.dart';
import 'package:test/test.dart';

final class _VfsTestHost implements EngineHost {
  final HeadlessHost _inner;
  @override
  final AssetLoader assets;

  _VfsTestHost(this.assets, [HeadlessHost? inner])
    : _inner = inner ?? HeadlessHost();

  @override
  SceneNode get sceneRoot => _inner.sceneRoot;
  @override
  Input get input => _inner.input;
  @override
  HeadlessGraphics get graphics => _inner.graphics;
  @override
  AudioDevice get audio => _inner.audio;
  @override
  KeyValueStore get storage => _inner.storage;

  @override
  void reportError(Object error, StackTrace stack) =>
      _inner.reportError(error, stack);
}

Uint8List _encodeUncompressedTga2x2() {
  final out = BytesBuilder()
    ..addByte(0)
    ..addByte(0)
    ..addByte(2)
    ..add(const [0, 0, 0, 0, 0])
    ..add(const [0, 0, 0, 0])
    ..add(const [2, 0])
    ..add(const [2, 0])
    ..addByte(32)
    ..addByte(0x28);
  for (var i = 0; i < 4; i++) {
    out.add([i * 40, i * 60, 200, 255]);
  }
  return out.toBytes();
}

Uint8List _encodeTestQmeshTriangle() {
  const headerBytes = 36;
  const stride = 14;
  const vertexCount = 3;
  final out = Uint8List(headerBytes + vertexCount * stride * 4);
  out[0] = 0x51; // Q
  out[1] = 0x4D; // M
  out[2] = 0x53; // S
  out[3] = 0x48; // H
  final view = ByteData.sublistView(out);
  view.setUint16(4, 1, Endian.little);
  view.setUint16(6, stride, Endian.little);
  view.setUint32(8, vertexCount, Endian.little);
  final bounds = [0.0, 0.0, 0.0, 1.0, 1.0, 0.0];
  for (var i = 0; i < 6; i++) {
    view.setFloat32(12 + i * 4, bounds[i], Endian.little);
  }
  final verts = <List<double>>[
    [0.0, 0.0, 0.0, 0.0, 0.0, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 0.0, 0.0, 0.0],
    [1.0, 0.0, 0.0, 0.0, 0.0, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 0.0, 0.0],
    [0.0, 1.0, 0.0, 0.0, 0.0, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 0.0, 1.0, 0.0],
  ];
  var offset = headerBytes;
  for (final v in verts) {
    for (final f in v) {
      view.setFloat32(offset, f, Endian.little);
      offset += 4;
    }
  }
  return out;
}

(int meshes, int materials) _countBoundNodes(ModelAsset model) {
  final meshes = <MeshHandle>{};
  final materials = <MaterialHandle>{};
  model.instantiate().traverse((node) {
    final m = node.mesh;
    if (m != null && m.isValid) meshes.add(m);
    final mat = node.material;
    if (mat != null && mat.isValid) materials.add(mat);
  });
  return (meshes.length, materials.length);
}

const String _testObj = '''
mtllib prop.mtl
v 0 0 0
v 2 0 0
v 0 2 0
vt 0 0
vt 1 0
vt 0 1
vn 0 0 1
usemtl stone
f 1/1/1 2/2/1 3/3/1
''';

const String _testMtl = '''
newmtl stone
Kd 0.5 0.5 0.55
map_Kd albedo.tga
''';

const String _testCubeLut = '''
TITLE "VFS Test LUT"
LUT_3D_SIZE 2
0.0 0.0 0.0
1.0 0.0 0.0
0.0 1.0 0.0
1.0 1.0 0.0
0.0 0.0 1.0
1.0 0.0 1.0
0.0 1.0 1.0
1.0 1.0 1.0
''';

void main() {
  group('P3-W11-A — VfsAssetLoader .pak & ref-counted AssetCatalog', () {
    late Uint8List pakBytes;

    setUp(() {
      final qmeshBytes = _encodeTestQmeshTriangle();
      final pkgManifest = jsonEncode({
        'schema': 'pixeldart-model-package-v1',
        'assetId': 'pkg-tri',
        'packageHash': '0123456789abcdef',
        'sourceFormat': 'obj',
        'boundsMin': [0.0, 0.0, 0.0],
        'boundsMax': [1.0, 1.0, 0.0],
        'materials': ['pkg-tri/mat0'],
        'parts': [
          {
            'id': 'part0',
            'materialSlot': 0,
            'boundsMin': [0.0, 0.0, 0.0],
            'boundsMax': [1.0, 1.0, 0.0],
            'lodFiles': {'LOD0': 'part0.qmesh'},
          },
        ],
      });

      final builder = PakBuilder()
        ..addText('models/prop.obj', _testObj)
        ..addText('models/prop.mtl', _testMtl)
        ..addBytes('models/albedo.tga', _encodeUncompressedTga2x2())
        ..addBytes('models/single.qmesh', qmeshBytes)
        ..addText('models/pkg/manifest.json', pkgManifest)
        ..addBytes('models/pkg/part0.qmesh', qmeshBytes)
        ..addText('luts/grade.cube', _testCubeLut)
        ..addText('data/hello.txt', 'hello-from-pak');
      pakBytes = builder.build();
    });

    test(
      'loads .obj, .qmesh, and model-package .json directly from .pak VFS with fallback: null',
      () async {
        final headless = HeadlessHost();
        final loader = VfsAssetLoader(
          fallback: null,
          graphics: headless.graphics,
        )..mountPakBytes('core', pakBytes);

        final objModel = await loader.loadModel('models/prop.obj');
        final objCounts = _countBoundNodes(objModel);
        expect(objCounts.$1, greaterThan(0));
        expect(objCounts.$2, greaterThan(0));
        expect(headless.graphics.liveMeshes, isNotEmpty);
        expect(headless.graphics.liveMaterials, isNotEmpty);

        final tex = await loader.loadTexture('models/albedo.tga');
        expect(tex.isValid, isTrue);
        expect(headless.graphics.liveTextures, hasLength(1));

        final qmeshModel = await loader.loadModel('models/single.qmesh');
        expect(_countBoundNodes(qmeshModel).$1, 1);

        final pkgModel = await loader.loadModel('models/pkg/manifest.json');
        expect(_countBoundNodes(pkgModel).$1, 1);

        final lut = await loader.loadLut('luts/grade.cube', key: 'grade');
        expect(lut.key, 'grade');
        expect(lut.size, 2);
        expect(lut.title, 'VFS Test LUT');
        expect(lut.rgbData.length, 24);

        expect(() => loader.loadModel('models/missing.obj'), throwsStateError);
      },
    );

    test(
      'AssetCatalog reference counting disposes GPU resources when refCount drops to 0',
      () async {
        final headless = HeadlessHost();
        final graphicsLinkedLoader = VfsAssetLoader(
          fallback: null,
          graphics: headless.graphics,
        )..mountPakBytes('core', pakBytes);
        final linkedHost = _VfsTestHost(graphicsLinkedLoader, headless);
        final engine = Engine(linkedHost);
        final catalog = engine.catalog;

        final evictedKeys = <String>[];
        catalog.onEvict<ModelAsset>((key, _) => evictedKeys.add('model:$key'));
        catalog.onEvict<TextureHandle>((key, _) => evictedKeys.add('tex:$key'));
        catalog.onEvict<LutAsset>((key, _) => evictedKeys.add('lut:$key'));

        expect(
          catalog.residencyState<ModelAsset>('prop'),
          AssetResidencyState.unreferenced,
        );

        final handle1 = await catalog.loadModel('prop', 'models/prop.obj');
        expect(catalog.refCount<ModelAsset>('prop'), 1);
        expect(
          catalog.residencyState<ModelAsset>('prop'),
          AssetResidencyState.resident,
        );
        final liveMeshesWhenLoaded = linkedHost.graphics.liveMeshes.length;
        final liveMaterialsWhenLoaded =
            linkedHost.graphics.liveMaterials.length;
        expect(liveMeshesWhenLoaded, greaterThan(0));
        expect(liveMaterialsWhenLoaded, greaterThan(0));

        final handle2 = catalog.acquireModel('prop');
        expect(catalog.refCount<ModelAsset>('prop'), 2);
        expect(handle1.refCount, 2);

        handle1.release();
        expect(handle1.isReleased, isTrue);
        expect(catalog.refCount<ModelAsset>('prop'), 1);
        expect(catalog.hasModel('prop'), isTrue);
        expect(linkedHost.graphics.liveMeshes.length, liveMeshesWhenLoaded);

        handle2.release();
        expect(catalog.refCount<ModelAsset>('prop'), 0);
        expect(catalog.hasModel('prop'), isFalse);
        expect(
          catalog.residencyState<ModelAsset>('prop'),
          AssetResidencyState.evicted,
        );
        expect(evictedKeys, contains('model:prop'));
        expect(linkedHost.graphics.liveMeshes, isEmpty);
        expect(linkedHost.graphics.liveMaterials, isEmpty);
        expect(linkedHost.graphics.liveTextures, isEmpty);

        final texHandle = await catalog.loadTexture(
          'albedo',
          'models/albedo.tga',
        );
        final lutHandle = await catalog.loadLut('grade', 'luts/grade.cube');
        expect(catalog.refCount<TextureHandle>('albedo'), 1);
        expect(catalog.refCount<LutAsset>('grade'), 1);
        expect(linkedHost.graphics.liveTextures, hasLength(1));

        texHandle.release();
        lutHandle.release();
        expect(catalog.hasTexture('albedo'), isFalse);
        expect(catalog.hasLut('grade'), isFalse);
        expect(linkedHost.graphics.liveTextures, isEmpty);
        expect(evictedKeys, containsAll(['tex:albedo', 'lut:grade']));

        // Also verify Engine.step drains Engine.streamingAssets automatically.
        final streamedText = engine.streamingAssets.loadText('data/hello.txt');
        engine.step(0.016);
        await pumpEventQueue();
        expect(await streamedText, 'hello-from-pak');
      },
    );

    test(
      'ModelRenderer ComponentSpec serializes inspector metadata cleanly',
      () {
        final registry = ComponentRegistry.defaults();
        final spec = registry.specByName('ModelRenderer');
        expect(spec, isNotNull);
        final instance = spec!.create();
        expect(instance, isA<ModelRenderer>());
        final json = spec.toJson(instance);
        expect(json['modelName'], 'empty');
        expect(json.containsKey('boundingRadius'), isTrue);
      },
    );
  });
}
