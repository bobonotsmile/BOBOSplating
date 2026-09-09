<script setup>
import {
  computed,
  defineAsyncComponent,
  onMounted,
  onUnmounted,
  ref,
} from "vue";
import { api, upload } from "./api.js";
import { bytes, elapsed, stages, stageState, statusNames } from "./jobs.js";
const SceneViewer = defineAsyncComponent(() => import("./SceneViewer.vue"));
const jobs = ref([]),
  selectedId = ref(null),
  settings = ref(null),
  logs = ref([]);
const file = ref(null),
  profile = ref("quick"),
  busy = ref(false),
  uploadProgress = ref(0);
const error = ref(""),
  connectionError = ref(""),
  showLogs = ref(false),
  tab = ref("scene");
const localScene = ref(null),
  localName = ref(""),
  dragOver = ref(false);
const videoInput = ref(null),
  sceneInput = ref(null);
const selected = computed(() =>
  jobs.value.find((j) => j.id === selectedId.value),
);
const completed = computed(
  () => jobs.value.filter((j) => j.status === "completed").length,
);
const active = computed(() => jobs.value.filter((j) => !j.isTerminal).length);
const sceneUrl = computed(
  () =>
    localScene.value ||
    (selected.value?.status === "completed"
      ? `/api/jobs/${selected.value.id}/scene.ply`
      : null),
);
let timer,
  stopped = false;
async function refresh() {
  try {
    jobs.value = await api("/jobs");
    settings.value = await api("/settings");
    if (!selectedId.value && jobs.value.length)
      selectedId.value = jobs.value[0].id;
    if (selectedId.value)
      logs.value = await api(`/jobs/${selectedId.value}/logs`);
    connectionError.value = "";
  } catch (e) {
    connectionError.value = `后端连接失败：${e.message}`;
  }
}
async function poll() {
  await refresh();
  if (!stopped) timer = setTimeout(poll, 2000);
}
onMounted(poll);
onUnmounted(() => {
  stopped = true;
  clearTimeout(timer);
  if (localScene.value) URL.revokeObjectURL(localScene.value);
});
function chooseVideo(candidate) {
  error.value = "";
  if (!candidate) return;
  if (!/\.(mp4|mov|mkv|webm)$/i.test(candidate.name)) {
    error.value = "请选择 MP4、MOV、MKV 或 WebM 视频。";
    return;
  }
  if (settings.value && candidate.size > settings.value.maxUploadBytes) {
    error.value = "视频超过上传大小限制。";
    return;
  }
  file.value = candidate;
}
async function createJob() {
  if (!file.value || busy.value) return;
  busy.value = true;
  uploadProgress.value = 0;
  error.value = "";
  try {
    const job = await upload(file.value, profile.value, (p) => {
      uploadProgress.value = p;
    });
    clearLocal();
    selectedId.value = job.id;
    file.value = null;
    tab.value = "activity";
    await refresh();
  } catch (e) {
    error.value = e.message;
  } finally {
    busy.value = false;
  }
}
async function cancelJob() {
  try {
    await api(`/jobs/${selectedId.value}/cancel`, { method: "POST" });
    await refresh();
  } catch (e) {
    error.value = e.message;
  }
}
function clearLocal() {
  if (localScene.value) URL.revokeObjectURL(localScene.value);
  localScene.value = null;
  localName.value = "";
}
function openScene(candidate) {
  if (!candidate) return;
  if (!/\.ply$/i.test(candidate.name)) {
    error.value = "本地预览请选择 Gaussian PLY 文件。";
    return;
  }
  clearLocal();
  localScene.value = URL.createObjectURL(candidate);
  localName.value = candidate.name;
  tab.value = "scene";
}
function selectJob(job) {
  clearLocal();
  selectedId.value = job.id;
  tab.value = job.status === "completed" ? "scene" : "activity";
  refresh();
}
</script>

<template>
  <div class="studio">
    <aside class="sidebar">
      <a class="brand" href="#" aria-label="BOBOSplating 首页"
        ><span class="brand-icon">B<span>✦</span></span>
        <div>
          BOBO<span>Splating</span><small>LOCAL SPATIAL STUDIO</small>
        </div></a
      >
      <div class="sidebar-label">工作空间</div>
      <div class="nav-active">
        <span>◈</span> 重建工作台 <span class="nav-dot"></span>
      </div>
      <section class="history">
        <div class="sidebar-label history-title">
          最近任务 <span>{{ jobs.length.toString().padStart(2, "0") }}</span>
        </div>
        <div v-if="!jobs.length" class="history-empty">
          还没有重建任务。<br />上传第一段视频，开始探索。
        </div>
        <button
          v-for="job in jobs"
          :key="job.id"
          class="job-item"
          :class="{ selected: selectedId === job.id && !localScene }"
          @click="selectJob(job)"
        >
          <span class="job-symbol" :class="job.status">{{
            job.status === "completed"
              ? "◇"
              : job.status === "running"
                ? "◌"
                : "▫"
          }}</span>
          <span class="job-text"
            ><strong>{{ job.name }}</strong
            ><small
              >{{ statusNames[job.status] }} ·
              {{ new Date(job.createdAt).toLocaleDateString() }}</small
            ></span
          >
        </button>
      </section>
      <div class="sidebar-footer">
        <span class="status-dot" :class="{ offline: connectionError }"></span
        >{{ connectionError ? "服务未连接" : "本地工作空间"
        }}<small>v0.1.0 · Apache-2.0</small>
      </div>
    </aside>
    <main>
      <header>
        <div class="breadcrumb">
          工作空间 <span>/</span> <strong>重建工作台</strong>
        </div>
        <button class="button secondary small" @click="sceneInput.click()">
          ↗ 打开本地 PLY</button
        ><input
          ref="sceneInput"
          type="file"
          accept=".ply"
          hidden
          @change="
            openScene($event.target.files[0]);
            $event.target.value = '';
          "
        />
      </header>
      <div class="content">
        <div class="page-heading">
          <div>
            <div class="eyebrow">FROM MOMENTS TO SPACES</div>
            <h1>让画面，成为空间<span>。</span></h1>
            <p>从一段视频开始，在本地重建可以自由探索的三维场景。</p>
          </div>
          <div class="overview">
            <div>
              <strong>{{ completed.toString().padStart(2, "0") }}</strong
              ><span>已完成场景</span>
            </div>
            <div>
              <strong>{{ active.toString().padStart(2, "0") }}</strong
              ><span>处理中任务</span>
            </div>
          </div>
        </div>
        <div v-if="connectionError" class="notice" role="status">
          {{ connectionError }}。本地 PLY 预览仍可使用。
        </div>
        <div
          v-else-if="settings?.toolsReady === false"
          class="notice"
          role="status"
        >
          当前服务器尚未配置
          {{ settings.missingTools.join("、") }}，暂不能创建重建任务。本地 PLY
          预览可正常使用。
        </div>
        <div v-if="error" class="notice error" role="alert">
          {{ error
          }}<button @click="error = ''" aria-label="关闭提示">×</button>
        </div>
        <div class="workspace-grid">
          <section class="panel create-panel">
            <div class="panel-heading">
              <span class="section-number">01</span>
              <h2>创建新场景</h2>
            </div>
            <label class="field-label"
              >视频素材 <span>VIDEO SOURCE</span></label
            >
            <div
              class="dropzone"
              :class="{ dragging: dragOver, loaded: file }"
              role="button"
              tabindex="0"
              @click="videoInput.click()"
              @keydown.enter="videoInput.click()"
              @keydown.space.prevent="videoInput.click()"
              @dragover.prevent="dragOver = true"
              @dragleave.prevent="dragOver = false"
              @drop.prevent="
                dragOver = false;
                chooseVideo($event.dataTransfer.files[0]);
              "
            >
              <div class="upload-symbol">{{ file ? "✓" : "+" }}</div>
              <strong>{{ file ? file.name : "拖入你的视频" }}</strong
              ><span>{{
                file ? bytes(file.size) + " · 点击更换" : "或点击选择本地文件"
              }}</span
              ><small
                >MP4 / MOV / MKV / WEBM
                {{
                  settings ? "· 最大 " + bytes(settings.maxUploadBytes) : ""
                }}</small
              >
            </div>
            <input
              ref="videoInput"
              type="file"
              accept=".mp4,.mov,.mkv,.webm"
              hidden
              @change="
                chooseVideo($event.target.files[0]);
                $event.target.value = '';
              "
            />
            <label class="field-label quality-label"
              >重建质量 <span>QUALITY</span></label
            >
            <div class="quality-options">
              <button
                v-for="p in settings?.profiles || [
                  { id: 'quick', name: '快速预览', steps: 5000 },
                  { id: 'balanced', name: '均衡重建', steps: 15000 },
                ]"
                :key="p.id"
                :class="{ chosen: profile === p.id }"
                @click="profile = p.id"
              >
                <span>{{ p.id === "quick" ? "ϟ" : "◈" }} {{ p.name }}</span
                ><small>{{ p.steps.toLocaleString() }} 步训练</small>
              </button>
            </div>
            <div class="capture-note">
              <strong>拍摄小提示</strong>
              <p>
                缓慢移动相机，围绕静止主体拍摄。保持清晰、光线稳定，并让相邻画面有足够重叠。
              </p>
            </div>
            <button
              class="button primary start-button"
              :disabled="
                !file ||
                busy ||
                !!connectionError ||
                settings?.toolsReady === false
              "
              @click="createJob"
            >
              {{ busy ? `正在上传 ${uploadProgress}%` : "开始重建" }}
              <span>→</span>
            </button>
            <p class="local-note">素材与训练结果保存在你的服务器</p>
          </section>
          <section class="panel scene-panel">
            <div class="scene-header">
              <div class="tabs">
                <button
                  :class="{ active: tab === 'scene' }"
                  @click="tab = 'scene'"
                >
                  三维预览</button
                ><button
                  :class="{ active: tab === 'activity' }"
                  @click="tab = 'activity'"
                >
                  任务进度
                  <span
                    v-if="selected && !selected.isTerminal"
                    class="status-dot"
                  ></span>
                </button>
              </div>
              <span class="format-tag">GAUSSIAN SPLATTING</span>
            </div>
            <div v-if="tab === 'scene'" class="preview-area">
              <SceneViewer
                v-if="sceneUrl"
                :key="sceneUrl"
                :url="sceneUrl"
                :name="localName || selected?.name"
              />
              <div v-else class="empty-scene">
                <div class="orb"><i></i><i></i><i></i><span>✦</span></div>
                <h3>
                  {{
                    selected && !selected.isTerminal
                      ? "你的场景正在形成"
                      : "下一个空间，由你创造"
                  }}
                </h3>
                <p>
                  {{
                    selected && !selected.isTerminal
                      ? "切换到任务进度，查看重建阶段与运行日志。"
                      : "上传视频开始重建，或打开已有 PLY 探索三维世界。"
                  }}
                </p>
                <button
                  class="text-button"
                  @click="
                    selected && !selected.isTerminal
                      ? (tab = 'activity')
                      : sceneInput.click()
                  "
                >
                  {{
                    selected && !selected.isTerminal
                      ? "查看进度 →"
                      : "打开本地 PLY →"
                  }}</button
                ><span class="axis-label">Y ↑ &nbsp; X → &nbsp; Z ↙</span>
              </div>
            </div>
            <div v-else class="activity-area">
              <template v-if="selected"
                ><div class="activity-title">
                  <div>
                    <small>当前任务</small>
                    <h3>{{ selected.name }}</h3>
                  </div>
                  <span class="badge" :class="selected.status">{{
                    statusNames[selected.status]
                  }}</span>
                </div>
                <div class="stage-list">
                  <div
                    v-for="([id, title], index) in stages"
                    :key="id"
                    class="stage"
                    :class="stageState(selected, index)"
                  >
                    <span>{{
                      stageState(selected, index) === "done" ? "✓" : index + 1
                    }}</span
                    ><strong>{{ title }}</strong
                    ><small v-if="stageState(selected, index) === 'active'">{{
                      id === "training" && selected.step
                        ? `${selected.step} / ${selected.totalSteps}`
                        : "进行中"
                    }}</small>
                  </div>
                </div>
                <p v-if="selected.error" class="job-error">
                  {{ selected.error }}
                </p>
                <div class="activity-actions">
                  <button
                    class="button secondary small"
                    @click="showLogs = !showLogs"
                  >
                    {{ showLogs ? "收起日志" : "查看运行日志" }}</button
                  ><button
                    v-if="!selected.isTerminal"
                    class="text-button danger"
                    @click="cancelJob"
                  >
                    取消任务
                  </button>
                </div>
                <pre v-if="showLogs" class="logs">{{
                  logs.join("\n") || "等待日志…"
                }}</pre>
              </template>
              <div v-else class="empty-activity">
                选择左侧任务，或创建一个新场景。
              </div>
            </div>
            <div class="scene-footer">
              <span
                ><span class="status-dot" :class="{ offline: !sceneUrl }"></span
                >{{
                  localScene
                    ? localName
                    : selected
                      ? statusNames[selected.status]
                      : "等待场景"
                }}</span
              ><a
                v-if="selected?.status === 'completed' && !localScene"
                class="download"
                :href="`/api/jobs/${selected.id}/scene.ply`"
                download
                >↓ 下载 PLY · {{ bytes(selected.resultBytes) }}</a
              ><span v-else>LOCAL FIRST</span>
            </div>
          </section>
        </div>
        <div class="metrics">
          <div>
            <span>注册视角</span
            ><strong
              >{{ selected?.registeredImages ?? "—"
              }}<small v-if="selected?.frames">
                / {{ selected.frames }}</small
              ></strong
            >
          </div>
          <div>
            <span>稀疏三维点</span
            ><strong>{{ selected?.points?.toLocaleString() ?? "—" }}</strong>
          </div>
          <div>
            <span>重投影误差</span
            ><strong
              >{{ selected?.reprojectionError?.toFixed(2) ?? "—"
              }}<small> px</small></strong
            >
          </div>
          <div>
            <span>处理耗时</span><strong>{{ elapsed(selected) }}</strong>
          </div>
        </div>
        <footer>
          <span>视频 → 相机重建 → Gaussian 训练 → 三维场景</span
          ><span>BOBOSplating / 本地三维重建工作台</span>
        </footer>
      </div>
    </main>
  </div>
</template>
