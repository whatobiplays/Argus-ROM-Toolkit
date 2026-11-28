const fs = require("node:fs");

const outputPath = process.env.GITHUB_OUTPUT;
if (!outputPath) {
  throw new Error("GITHUB_OUTPUT is unavailable");
}

const available = Object.prototype.hasOwnProperty.call(process.env, "ACTIONS_CACHE_MODE");
const value = available ? process.env.ACTIONS_CACHE_MODE : "";
const valueBase64 = Buffer.from(value, "utf8").toString("base64");
fs.appendFileSync(
  outputPath,
  `available=${available}\nvalue_base64=${valueBase64}\n`,
  "utf8",
);
