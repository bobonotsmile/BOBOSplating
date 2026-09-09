export async function api(path, options = {}) {
  const response = await fetch(`/api${path}`, {
    ...options,
    headers: { "X-Bobo-Client": "web", ...options.headers },
  });
  if (!response.ok) {
    const message = await response.json().catch(() => ({}));
    throw new Error(message.error || `请求失败（${response.status}）`);
  }
  const text = await response.text();
  return text ? JSON.parse(text) : null;
}
export function upload(file, profile, onProgress) {
  return new Promise((resolve, reject) => {
    const xhr = new XMLHttpRequest();
    xhr.open("POST", "/api/jobs");
    xhr.setRequestHeader("X-Bobo-Client", "web");
    xhr.upload.onprogress = (e) => {
      if (e.lengthComputable)
        onProgress(Math.round((e.loaded / e.total) * 100));
    };
    xhr.onerror = () => reject(new Error("上传连接中断，请检查服务状态。"));
    xhr.onload = () => {
      let data = {};
      try {
        data = JSON.parse(xhr.responseText);
      } catch {
        /* Nginx may return an HTML error. */
      }
      if (xhr.status >= 200 && xhr.status < 300) resolve(data);
      else
        reject(
          new Error(
            data.error ||
              (xhr.status === 413
                ? "视频超过上传限制。"
                : `上传失败（${xhr.status}）`),
          ),
        );
    };
    const form = new FormData();
    form.append("video", file);
    form.append("profile", profile);
    xhr.send(form);
  });
}
