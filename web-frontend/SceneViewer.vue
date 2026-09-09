<script setup>
import { onMounted, onUnmounted, ref } from "vue";
import * as THREE from "three";
import { OrbitControls } from "three/addons/controls/OrbitControls.js";
import { SparkRenderer, SplatMesh } from "@sparkjsdev/spark";
const props = defineProps({
  url: { type: String, required: true },
  name: String,
});
const host = ref(null),
  loading = ref(true),
  error = ref(""),
  count = ref(0);
let renderer,
  controls,
  scene,
  camera,
  mesh,
  spark,
  observer,
  dead = false,
  initial;
const abort = new AbortController();
function reset() {
  if (!initial || !controls) return;
  camera.position.copy(initial.position);
  camera.up.set(0, 1, 0);
  controls.target.copy(initial.target);
  controls.update();
}
function flip() {
  if (mesh) {
    mesh.rotation.z += Math.PI;
    fit();
  }
}
function fit() {
  mesh.updateMatrixWorld(true);
  const box = mesh.getBoundingBox().applyMatrix4(mesh.matrixWorld);
  const center = box.getCenter(new THREE.Vector3());
  const radius = box.getSize(new THREE.Vector3()).length() / 2;
  if (!Number.isFinite(radius) || radius <= 0)
    throw new Error("模型为空或坐标无效。");
  const verticalHalf = THREE.MathUtils.degToRad(camera.fov / 2);
  const horizontalHalf = Math.atan(Math.tan(verticalHalf) * camera.aspect);
  const distance =
    (radius / Math.sin(Math.min(verticalHalf, horizontalHalf))) * 1.2;
  camera.near = Math.max(radius / 10000, 0.0001);
  camera.far = Math.max(distance * 100, 100);
  camera.updateProjectionMatrix();
  initial = {
    target: center,
    position: center.clone().add(new THREE.Vector3(0, radius * 0.25, distance)),
  };
  reset();
}
function cleanup() {
  observer?.disconnect();
  renderer?.setAnimationLoop(null);
  controls?.dispose();
  mesh?.dispose();
  spark?.dispose();
  renderer?.dispose();
  renderer?.domElement.remove();
}
onMounted(async () => {
  try {
    renderer = new THREE.WebGLRenderer({ antialias: false, alpha: false });
    renderer.setPixelRatio(Math.min(window.devicePixelRatio, 2));
    renderer.setClearColor("#11181c");
    host.value.appendChild(renderer.domElement);
    scene = new THREE.Scene();
    camera = new THREE.PerspectiveCamera(50, 1, 0.01, 1000);
    controls = new OrbitControls(camera, renderer.domElement);
    controls.enableDamping = true;
    spark = new SparkRenderer({ renderer });
    scene.add(spark);
    observer = new ResizeObserver(() => {
      const width = host.value?.clientWidth || 1,
        height = host.value?.clientHeight || 1;
      renderer.setSize(width, height);
      camera.aspect = width / height;
      camera.updateProjectionMatrix();
    });
    observer.observe(host.value);
    const response = await fetch(props.url, { signal: abort.signal });
    if (!response.ok) throw new Error(`模型读取失败（${response.status}）`);
    const fileBytes = await response.arrayBuffer();
    if (dead) return;
    mesh = new SplatMesh({ fileBytes, fileName: "scene.ply" });
    // COLMAP uses image coordinates with +Y down.
    mesh.rotation.x = Math.PI;
    await mesh.initialized;
    if (dead) {
      mesh.dispose();
      return;
    }
    scene.add(mesh);
    fit();
    count.value = mesh.splats?.getNumSplats() ?? 0;
    loading.value = false;
    renderer.setAnimationLoop(() => {
      controls.update();
      renderer.render(scene, camera);
    });
  } catch (e) {
    if (dead) return;
    error.value = `无法显示场景：${e.message}`;
    loading.value = false;
    cleanup();
  }
});
onUnmounted(() => {
  dead = true;
  abort.abort();
  cleanup();
});
</script>
<template>
  <div class="viewer-shell">
    <div ref="host" class="viewer-canvas"></div>
    <div v-if="loading" class="viewer-message">
      <span class="loading-ring"></span>正在加载三维场景…
    </div>
    <div v-if="error" class="viewer-message viewer-error" role="alert">
      {{ error }}<small>请确认浏览器支持 WebGL2，并已开启硬件加速。</small>
    </div>
    <div v-if="!loading && !error" class="viewer-toolbar">
      <span>{{
        count ? count.toLocaleString() + " Gaussians" : "Gaussian 场景"
      }}</span
      ><button @click="reset">重置视角</button
      ><button @click="flip">上下翻转</button>
    </div>
    <div v-if="!error" class="viewer-help">左键旋转 · 右键平移 · 滚轮缩放</div>
  </div>
</template>
