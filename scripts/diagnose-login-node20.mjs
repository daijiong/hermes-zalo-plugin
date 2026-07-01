import fs from "node:fs";
import path from "node:path";
import { Zalo, LoginQRCallbackEventType } from "zca-js";

const dir = path.join(process.env.USERPROFILE || process.env.HOME || ".", ".hermes-zalo");
fs.mkdirSync(dir, { recursive: true });

const qrPath = path.join(dir, "qr-node20-diagnostic-live.png");
const credPath = path.join(dir, "credentials.json");
const userAgent =
  "Mozilla/5.0 (Windows NT 10.0; Win64; x64; rv:133.0) Gecko/20100101 Firefox/133.0";

const zalo = new Zalo({ logging: true, selfListen: true });

console.log("[diag] start", new Date().toISOString());
console.log("[diag] node", process.version);
console.log("[diag] qrPath", qrPath);

try {
  const api = await zalo.loginQR({ userAgent, qrPath }, (event) => {
    const name = LoginQRCallbackEventType[event.type] || String(event.type);
    const data = event.data || {};
    console.log(
      "[diag-event]",
      name,
      JSON.stringify({
        status: data.status,
        display_name: data.display_name,
        code: data.code,
      }).slice(0, 500),
    );

    if (event.type === LoginQRCallbackEventType.QRCodeGenerated) {
      fs.writeFileSync(
        qrPath,
        String(data.image || "").replace(/^data:image\/png;base64,/, ""),
        "base64",
      );
      console.log("[diag] qr-written", qrPath, fs.statSync(qrPath).size);
    }

    if (event.type === LoginQRCallbackEventType.GotLoginInfo) {
      fs.writeFileSync(
        credPath,
        JSON.stringify(
          { cookie: data.cookie, imei: data.imei, userAgent: data.userAgent },
          null,
          2,
        ),
        "utf-8",
      );
      console.log("[diag] credentials-written", credPath);
    }
  });

  console.log("[diag] login-ok", !!api);
  process.exit(0);
} catch (e) {
  console.error("[diag-failed]", e && e.stack ? e.stack : e);
  process.exit(1);
}
