import { ProxyAgent, setGlobalDispatcher } from "undici";

const proxy =
  process.env.HTTPS_PROXY ||
  process.env.https_proxy ||
  process.env.ALL_PROXY ||
  process.env.all_proxy ||
  process.env.HTTP_PROXY ||
  process.env.http_proxy ||
  "";

function proxyForLog(value) {
  try {
    const url = new URL(value);
    if (url.username) {
      url.username = "[user]";
    }
    if (url.password) {
      url.password = "[password]";
    }
    return url.toString();
  } catch {
    return "[configured]";
  }
}

if (proxy) {
  setGlobalDispatcher(new ProxyAgent(proxy));
  console.log(`[node-proxy] using ${proxyForLog(proxy)}`);
}
