import sys, json, subprocess, os, re
from pathlib import Path

inFile = sys.argv[1]
outFile = sys.argv[2]
profilePath = Path(sys.argv[3] if len(sys.argv) > 3 else "build-profile.json5").resolve()
signingConfigName = sys.argv[4] if len(sys.argv) > 4 else os.environ.get("WINEHUA_SIGNING_CONFIG", "")

# Read JSON5 file and convert to valid JSON
with profilePath.open() as f:
    content = f.read()
# Remove trailing commas before } or ]
content = re.sub(r',\s*([}\]])', r'\1', content)
# Remove comments
content = re.sub(r'//.*$', '', content, flags=re.MULTILINE)
profile = json.loads(content)

signingConfigs = profile["app"]["signingConfigs"]
selected = signingConfigs[0]
if signingConfigName:
    selected = next(
        (item for item in signingConfigs if item.get("name") == signingConfigName),
        None,
    )
    if selected is None:
        raise ValueError(f"signing config not found: {signingConfigName}")
config = selected["material"]

def material_path(value):
    path = Path(value)
    return path if path.is_absolute() else (profilePath.parent / path).resolve()

certPath = material_path(config["certpath"])
profileFile = material_path(config["profile"])
storeFile = material_path(config["storeFile"])
basePath = certPath.parent
sdkToolDir = os.environ['TOOL_HOME']

# Decrypt passwords using sign.js
keyPwd = subprocess.check_output(
    ["node", "sign.js", str(basePath.absolute()), config["keyPassword"]], encoding="utf-8"
).strip()
keystorePwd = subprocess.check_output(
    ["node", "sign.js", str(basePath.absolute()), config["storePassword"]], encoding="utf-8"
).strip()

# Build the signing command without a shell. Do not log the decrypted
# passwords: CI/build logs are part of the release threat model.
jar = f"{sdkToolDir}/sdk/default/openharmony/toolchains/lib/hap-sign-tool.jar"
cmd = [
    "java", "-jar", jar, "sign-app",
    "-keyAlias", config["keyAlias"],
    "-signAlg", config["signAlg"],
    "-mode", "localSign",
    "-appCertFile", str(certPath),
    "-profileFile", str(profileFile),
    "-inFile", inFile,
    "-keystoreFile", str(storeFile),
    "-outFile", outFile,
    "-keyPwd", keyPwd,
    "-keystorePwd", keystorePwd,
]
subprocess.run(cmd, check=True)
