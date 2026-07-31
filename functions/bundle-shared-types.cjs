// Copies the built @cohyve/shared-types package into functions/shared-types/
// so that `firebase deploy` can bundle it (Cloud Build only sees functions/).
const fs = require("fs");
const path = require("path");

const src = path.resolve(__dirname, "..", "packages", "shared-types");
const dst = path.resolve(__dirname, "shared-types");

// Clean target
fs.rmSync(dst, { recursive: true, force: true });
fs.mkdirSync(dst, { recursive: true });

// Build shared-types first if dist doesn't exist
const distDir = path.join(src, "dist");
if (!fs.existsSync(distDir)) {
  const { execSync } = require("child_process");
  execSync("npm run build", { cwd: src, stdio: "inherit" });
}

// Copy dist/
copyDirSync(path.join(src, "dist"), path.join(dst, "dist"));

// Copy package.json (strip workspace-only fields)
const pkg = JSON.parse(fs.readFileSync(path.join(src, "package.json"), "utf8"));
delete pkg.scripts;
delete pkg.devDependencies;
fs.writeFileSync(path.join(dst, "package.json"), JSON.stringify(pkg, null, 2));

console.log("  bundled @cohyve/shared-types into functions/shared-types/");

function copyDirSync(srcDir, dstDir) {
  fs.mkdirSync(dstDir, { recursive: true });
  for (const entry of fs.readdirSync(srcDir, { withFileTypes: true })) {
    const s = path.join(srcDir, entry.name);
    const d = path.join(dstDir, entry.name);
    if (entry.isDirectory()) copyDirSync(s, d);
    else fs.copyFileSync(s, d);
  }
}
