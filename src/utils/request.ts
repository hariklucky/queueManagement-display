import type { RequestClient, RequestConfig } from "./request.types";
import { appFetch } from "./httpFetch";
import { getBusinessHallId } from "./terminalContext";

const baseURL = import.meta.env.VITE_API_BASE_URL || "/api";

function buildUrl(url: string, params?: RequestConfig["params"]) {
  const path = url.startsWith("http")
    ? url
    : `${baseURL.replace(/\/$/, "")}/${url.replace(/^\//, "")}`;

  if (!params) {
    return path;
  }

  const search = new URLSearchParams();
  Object.entries(params).forEach(([key, value]) => {
    if (value != null) {
      search.set(key, String(value));
    }
  });

  const query = search.toString();
  if (!query) {
    return path;
  }

  return `${path}${path.includes("?") ? "&" : "?"}${query}`;
}

function validateResponseData(data: unknown): unknown {
  if (typeof data === "string" && data.trimStart().startsWith("<!DOCTYPE")) {
    throw new Error(
      `接口返回了 HTML 页面而非 JSON，请检查 VITE_API_BASE_URL（当前：${baseURL}）。` +
        "打包后的桌面应用不会走 Vite 代理，需配置为后端完整地址后重新构建。",
    );
  }

  if (data != null && typeof data !== "object") {
    throw new Error("接口返回了非 JSON 数据，请检查后端地址与网络连接");
  }

  return data;
}

async function sendRequest<T>(
  method: string,
  url: string,
  data?: unknown,
  config?: RequestConfig,
): Promise<T> {
  const headers: Record<string, string> = {
    Accept: "application/json",
  };

  const hallId = getBusinessHallId();
  if (hallId) {
    headers["X-Business-Hall-Id"] = hallId;
  }

  let body: string | undefined;
  if (data !== undefined) {
    headers["Content-Type"] = "application/json";
    body = JSON.stringify(data);
  }

  const response = await appFetch(buildUrl(url, config?.params), {
    method,
    headers,
    body,
  });

  const text = await response.text();
  let responseData: unknown = null;

  if (text) {
    try {
      responseData = JSON.parse(text);
    } catch {
      responseData = text;
    }
  }
  console.log("RRRRRRRRRRRRRRRRRRR", responseData);
  if (!response.ok) {
    throw {
      message:
        (responseData as { message?: string; msg?: string })?.message ||
        (responseData as { message?: string; msg?: string })?.msg ||
        response.statusText ||
        "请求失败",
      response: {
        status: response.status,
        data: responseData,
      },
    };
  }

  return validateResponseData(responseData) as T;
}

const request: RequestClient = {
  get<T>(url: string, config?: RequestConfig) {
    return sendRequest<T>("GET", url, undefined, config);
  },
  post<T>(url: string, data?: unknown, config?: RequestConfig) {
    return sendRequest<T>("POST", url, data, config);
  },
  put<T>(url: string, data?: unknown, config?: RequestConfig) {
    return sendRequest<T>("PUT", url, data, config);
  },
  delete<T>(url: string, config?: RequestConfig) {
    return sendRequest<T>("DELETE", url, undefined, config);
  },
};

export default request;
