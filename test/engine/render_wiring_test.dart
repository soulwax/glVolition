/// Decoupled GPU system wiring tests: LightProbeGI, Lighting2D, SoftBodyXPBD,
/// DrawBatcher, and RenderGraph against HeadlessHost / HeadlessGraphics.
library;

import 'dart:typed_data';

import 'package:gl_volition/gl_volition.dart';
import 'package:test/test.dart';

void main() {
  group('P4-W12-D — Decoupled GPU Systems Wiring', () {
    late HeadlessHost host;
    late Engine engine;

    setUp(() {
      host = HeadlessHost();
      engine = Engine(host);
    });

    group('1. LightProbeGI SH3 Irradiance Uniforms', () {
      test('evaluates & uploads 9-band SH3 uniforms and respects cleanup', () {
        final gfx = host.graphics;
        final go = engine.scene.createGameObject(
          'ProbeGI',
          position: const Vec3(2.0, 1.0, -3.0),
        );
        final gi = go.addComponent(
          LightProbeVolumeComponent(
            minCorner: const Vec3(-5, -2, -5),
            maxCorner: const Vec3(5, 4, 5),
            nx: 3,
            ny: 3,
            nz: 3,
            intensity: 1.5,
          ),
        );

        // Add a point light to bake some radiance
        engine.scene.createGameObject(
          'Lantern',
          position: const Vec3(2.0, 1.5, -2.5),
          components: [
            Light.point(
              color: const LinearColor(1.0, 0.8, 0.4),
              intensity: 3.0,
              range: 8.0,
            ),
          ],
        );

        engine.step(0.016);
        gi.bakeFromScene();

        // 1. Sync to renderer
        gi.syncToRenderer(gfx);

        final uniforms = gfx.shaderUniforms[ShaderSlot.shadowedWorld];
        expect(uniforms, isNotNull);

        // Verify SH3 enabled uniform
        final enabledUni =
            uniforms![RenderingShaderContracts.sh3EnabledUniform];
        expect(enabledUni, isNotNull);
        expect(enabledUni!.x, equals(1.0));

        // Verify SH3 origin uniform
        final originUni = uniforms[RenderingShaderContracts.sh3OriginUniform];
        expect(originUni, isNotNull);
        expect(originUni!.x, closeTo(2.0, 1e-4));
        expect(originUni.y, closeTo(1.0, 1e-4));
        expect(originUni.z, closeTo(-3.0, 1e-4));

        // Verify SH3 intensity uniform
        final intensityUni =
            uniforms[RenderingShaderContracts.sh3IntensityUniform];
        expect(intensityUni, isNotNull);
        expect(intensityUni!.x, closeTo(1.5, 1e-4));

        // Verify all 9 SH3 coefficient uniforms (c0..c8)
        for (var i = 0; i < RenderingShaderContracts.sh3CoefficientCount; i++) {
          final uniName = RenderingShaderContracts.sh3CoefficientUniform(i);
          final coeffUni = uniforms[uniName];
          expect(coeffUni, isNotNull, reason: 'Missing uniform $uniName');
          expect(coeffUni!.glslType, equals('vec3'));
          expect(coeffUni.x.isFinite, isTrue);
          expect(coeffUni.y.isFinite, isTrue);
          expect(coeffUni.z.isFinite, isTrue);
        }

        // L00 band should have non-zero energy from sky / lantern
        final l00 =
            uniforms[RenderingShaderContracts.sh3CoefficientUniform(0)]!;
        expect(l00.x + l00.y + l00.z, greaterThan(0.0));

        // 2. Disable / cleanup turns off SH3 enabled uniform
        gi.cleanup(gfx);
        final disabledUni =
            gfx.shaderUniforms[ShaderSlot
                .shadowedWorld]![RenderingShaderContracts.sh3EnabledUniform];
        expect(disabledUni!.x, equals(0.0));
      });
    });

    group('2. Lighting2D Overlay Pass & Uniforms', () {
      test('composes 2D lights/casters and declares/removes overlay pass', () {
        final gfx = host.graphics;

        // Add 2D lights
        engine.scene.createGameObject(
          'Torch2D',
          position: const Vec3(5.0, 3.0, 0.0),
          components: [
            Light2DComponent(
              color: const LinearColor(1.0, 0.6, 0.2),
              intensity: 2.0,
              radius: 12.0,
            ),
          ],
        );

        // Add 2D shadow caster
        engine.scene.createGameObject(
          'Wall2D',
          position: const Vec3(2.0, 2.0, 0.0),
          components: [ShadowCaster2DComponent.box(const Vec2(1.0, 2.0))],
        );

        final lightingGo = engine.scene.createGameObject('LightingManager');
        final lighting2D = lightingGo.addComponent(
          Lighting2DComponent(
            ambientColor: const LinearColor(0.08, 0.09, 0.12),
            priority: 5,
          ),
        );

        engine.step(0.016);

        // 1. Sync to renderer
        lighting2D.syncToRenderer(gfx);

        expect(
          gfx.declaredRenderPasses.containsKey(
            RenderingShaderContracts.lighting2dPassId,
          ),
          isTrue,
        );

        final pass = gfx
            .declaredRenderPasses[RenderingShaderContracts.lighting2dPassId]!;
        expect(pass.anchor, equals(RenderPassAnchor.afterWorld));
        expect(pass.priority, equals(5));
        expect(pass.enabled, isTrue);

        // Verify pass uniforms
        final ambient =
            pass.uniforms[RenderingShaderContracts.lighting2dAmbientUniform];
        expect(ambient, isNotNull);
        expect(ambient!.x, closeTo(0.08, 1e-4));
        expect(ambient.y, closeTo(0.09, 1e-4));
        expect(ambient.z, closeTo(0.12, 1e-4));

        final lightCount =
            pass.uniforms[RenderingShaderContracts.lighting2dLightCountUniform];
        expect(lightCount, isNotNull);
        expect(lightCount!.integer, equals(1));

        final casterCount = pass
            .uniforms[RenderingShaderContracts.lighting2dCasterCountUniform];
        expect(casterCount, isNotNull);
        expect(casterCount!.integer, greaterThan(0));

        // 2. Texture binding test
        final texHandle = gfx.createTexture(width: 256, height: 256);
        lighting2D.lightmapTexture = texHandle;
        lighting2D.syncToRenderer(gfx);

        final updatedPass = gfx
            .declaredRenderPasses[RenderingShaderContracts.lighting2dPassId]!;
        expect(
          updatedPass.textures[RenderingShaderContracts
              .lighting2dLightmapTexture],
          equals(texHandle),
        );

        // 3. Cleanup removes the declared pass
        lighting2D.cleanup(gfx);
        expect(
          gfx.declaredRenderPasses.containsKey(
            RenderingShaderContracts.lighting2dPassId,
          ),
          isFalse,
        );
      });
    });

    group('3. SoftBodyXPBD Dynamic Mesh Upload', () {
      test(
        'recomputes deformed vertices & normals and uploads dynamic mesh',
        () {
          final gfx = host.graphics;
          final go = engine.scene.createGameObject(
            'JellyCube',
            position: const Vec3(0, 5, 0),
          );
          final softBody = go.addComponent(
            SoftBodyXpbdComponent(halfExtent: 1.0, floorY: 0.0, substeps: 4),
          );

          final initialUploadCount = gfx.meshUploadCount;

          // 1. Sync to renderer
          softBody.syncToRenderer(gfx);

          expect(gfx.meshUploadCount, equals(initialUploadCount + 1));
          expect(softBody.meshHandle, isNotNull);
          expect(gfx.updatedMeshes.containsKey(softBody.meshHandle), isTrue);

          final meshData = gfx.updatedMeshes[softBody.meshHandle]!;
          expect(
            meshData.layout,
            equals(VertexLayoutDescriptor.compatibility14),
          );
          expect(meshData.vertexCount, equals(24)); // 6 faces * 4 vertices
          expect(meshData.localBounds.isValid, isTrue);

          // Verify vertices have finite positions and normalized normals
          for (var i = 0; i < 24; i++) {
            final base = i * 14;
            final px = meshData.vertices[base + 0];
            final py = meshData.vertices[base + 1];
            final pz = meshData.vertices[base + 2];
            final nx = meshData.vertices[base + 3];
            final ny = meshData.vertices[base + 4];
            final nz = meshData.vertices[base + 5];

            expect(px.isFinite, isTrue);
            expect(py.isFinite, isTrue);
            expect(pz.isFinite, isTrue);

            final normalLen = nx * nx + ny * ny + nz * nz;
            expect(normalLen, closeTo(1.0, 1e-3));
          }

          // 2. Deform via node displacement and physics step
          final initialVertices = Float32List.fromList(meshData.vertices);
          softBody.solver.nodes[0].position =
              softBody.solver.nodes[0].position +
              const VerletVec3(0.5, -0.8, 0.3);
          softBody.applyImpulse(const Vec3(1.0, -3.0, 0.5));
          softBody.stepPhysics(0.05);
          softBody.syncToRenderer(gfx);

          expect(gfx.meshUploadCount, equals(initialUploadCount + 2));
          final deformedData = gfx.updatedMeshes[softBody.meshHandle]!;

          // At least some vertices moved due to deformation
          var diffFound = false;
          for (var i = 0; i < 24 * 14; i += 14) {
            if ((deformedData.vertices[i + 0] - initialVertices[i + 0]).abs() >
                    1e-4 ||
                (deformedData.vertices[i + 1] - initialVertices[i + 1]).abs() >
                    1e-4) {
              diffFound = true;
              break;
            }
          }
          expect(diffFound, isTrue);
        },
      );
    });

    group('4. DrawBatcher Indirect Batch Submission', () {
      test(
        'clusters scene renderers and dispatches SubmittedIndirectBatch',
        () {
          final gfx = host.graphics;

          // Create dummy mesh and material handles
          final mesh1 = gfx.createMesh(
            MeshData(
              layout: VertexLayoutDescriptor.compatibility14,
              vertices: Float32List(14 * 3),
              indices: [0, 1, 2],
              localBounds: const Aabb(Vec3(-1, -1, -1), Vec3(1, 1, 1)),
            ),
          );
          final mesh2 = gfx.createMesh(
            MeshData(
              layout: VertexLayoutDescriptor.compatibility14,
              vertices: Float32List(14 * 3),
              indices: [0, 1, 2],
              localBounds: const Aabb(Vec3(-1, -1, -1), Vec3(1, 1, 1)),
            ),
          );
          final mat1 = gfx.createMaterial(
            const MaterialDefinition(key: 'mat_stone'),
          );
          final mat2 = gfx.createMaterial(
            const MaterialDefinition(key: 'mat_wood'),
          );

          // Create game objects with mesh renderers
          final go1 = engine.scene.createGameObject(
            'Obj1',
            position: const Vec3(0, 0, 0),
          );
          final mr1 = go1.addComponent(MeshRenderer());
          mr1.mesh = mesh1;
          mr1.material = mat1;

          final go2 = engine.scene.createGameObject(
            'Obj2',
            position: const Vec3(2, 0, 1),
          );
          final mr2 = go2.addComponent(MeshRenderer());
          mr2.mesh = mesh2;
          mr2.material = mat2;

          final batcherGo = engine.scene.createGameObject('Batcher');
          final batcher = batcherGo.addComponent(
            DrawBatcherComponent(cellSize: 8.0),
          );

          engine.step(0.016);

          // 1. Sync to renderer
          final initialBatchCount = gfx.indirectBatches.length;
          final submitted = batcher.syncToRenderer(gfx);

          expect(gfx.indirectBatches.length, equals(initialBatchCount + 1));
          expect(
            submitted.passId,
            equals(RenderingShaderContracts.indirectBatchPassId),
          );
          expect(submitted.instanceCount, equals(2));
          expect(submitted.drawCommandCount, greaterThan(0));
          expect(submitted.meshes, contains(mesh1));
          expect(submitted.meshes, contains(mesh2));
          expect(submitted.materials, contains(mat1));
          expect(submitted.materials, contains(mat2));
        },
      );
    });

    group('5. RenderGraph Custom Passes & Reconciliation', () {
      test(
        'converts DAG passes to RenderPassDecl, reconciles & removes cleanly',
        () {
          final gfx = host.graphics;
          final go = engine.scene.createGameObject('RenderGraph');
          final rg = go.addComponent(
            RenderGraphComponent(
              viewportWidth: 1920,
              viewportHeight: 1080,
              includePostProcessPass: true,
            ),
          );

          // 1. Sync compiled graph to renderer
          rg.syncToRenderer(gfx);

          // Verify standard scheduled passes are declared
          expect(gfx.declaredRenderPasses.containsKey('DepthPrePass'), isTrue);
          expect(
            gfx.declaredRenderPasses.containsKey('OpaqueLighting'),
            isTrue,
          );
          expect(gfx.declaredRenderPasses.containsKey('BloomExtract'), isTrue);
          expect(
            gfx.declaredRenderPasses.containsKey('ToneMapPresent'),
            isTrue,
          );

          final depthPass = gfx.declaredRenderPasses['DepthPrePass']!;
          expect(depthPass.anchor, equals(RenderPassAnchor.beforeDepth));
          expect(depthPass.attachments.any((a) => a.name == 'depth_z'), isTrue);

          final tonePass = gfx.declaredRenderPasses['ToneMapPresent']!;
          expect(tonePass.anchor, equals(RenderPassAnchor.beforePresent));
          expect(tonePass.dependsOn, contains('OpaqueLighting'));
          expect(tonePass.dependsOn, contains('BloomExtract'));

          // 2. Add custom pass and reconcile
          const customPass = RenderPassDecl(
            id: 'CustomLUTGrading',
            anchor: RenderPassAnchor.afterGrade,
            priority: 42,
            uniforms: {'uLutBlend': ShaderUniform.float(0.75)},
          );
          rg.addCustomPass(customPass);
          rg.syncToRenderer(gfx);

          expect(
            gfx.declaredRenderPasses.containsKey('CustomLUTGrading'),
            isTrue,
          );
          expect(
            gfx.declaredRenderPasses['CustomLUTGrading']!.priority,
            equals(42),
          );

          // 3. Remove custom pass and reconcile
          rg.removeCustomPass('CustomLUTGrading');
          rg.syncToRenderer(gfx);

          expect(
            gfx.declaredRenderPasses.containsKey('CustomLUTGrading'),
            isFalse,
            reason: 'Custom pass was not removed during reconciliation',
          );
          // Standard passes must still remain active
          expect(
            gfx.declaredRenderPasses.containsKey('OpaqueLighting'),
            isTrue,
          );

          // 4. Clear all declared passes
          rg.clearDeclaredPasses(gfx);
          expect(gfx.declaredRenderPasses.isEmpty, isTrue);
        },
      );
    });
  });
}
