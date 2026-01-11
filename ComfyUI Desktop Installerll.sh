#!/usr/bin/env bash
set -e

APPNAME="ComfyUI Desktop Installer"
LOG="$HOME/.comfyui_install.log"
exec > >(tee -a "$LOG") 2>&1

echo "=== $APPNAME START ==="

# 1️⃣ Проверка зависимостей
echo "Checking dependencies..."
sudo apt update
sudo apt install -y git python3 curl libfuse2 zenity python3-venv python3-pip

# 2️⃣ Определяем путь установки
INSTALL_PATH="$HOME/ComfyUI-Desktop"
mkdir -p "$INSTALL_PATH"
echo "Install path: $INSTALL_PATH"

# 3️⃣ Проверка GPU
if command -v nvidia-smi >/dev/null; then
  GPU=1
  echo "NVIDIA GPU detected"
else
  GPU=0
  echo "No NVIDIA GPU detected"
fi

# 4️⃣ Выбор режима
if [ "$GPU" -eq 1 ]; then
  MODE=$(zenity --list --title="Select ComfyUI Mode" --column="Mode" "GPU (CUDA)" "Low VRAM" "CPU / Safe Mode")
else
  MODE="CPU / Safe Mode"
fi
echo "$MODE" > "$INSTALL_PATH/.run_mode"

# 5️⃣ Загрузка ComfyUI
if [ ! -d "$INSTALL_PATH/comfyui" ]; then
  echo "Cloning ComfyUI repository..."
  git clone https://github.com/comfyanonymous/ComfyUI.git "$INSTALL_PATH/comfyui"
fi

# 6️⃣ Создание виртуального окружения (embedded Python)
VENV_PATH="$INSTALL_PATH/venv"
if [ ! -d "$VENV_PATH" ]; then
  echo "Creating virtual environment..."
  python3 -m venv "$VENV_PATH"
fi

source "$VENV_PATH/bin/activate"

# 7️⃣ Установка зависимостей
echo "Installing Python dependencies..."
pip install --upgrade pip
pip install -r "$INSTALL_PATH/comfyui/requirements.txt"

# 8️⃣ Создание скрипта Safe Launcher с rollback
cat > "$INSTALL_PATH/safe_launcher.sh" <<'EOF'
#!/usr/bin/env bash
BASE="$HOME/ComfyUI-Desktop"
cd "$BASE/comfyui"
git rev-parse HEAD > "$BASE/.last_good"
source "$BASE/venv/bin/activate"
MODE=$(cat "$BASE/.run_mode")
ARGS="--listen 127.0.0.1 --port 8188"

case "$MODE" in
  "GPU (CUDA)") ARGS="$ARGS --cuda-malloc" ;;
  "Low VRAM") ARGS="$ARGS --lowvram --force-fp16" ;;
  "CPU / Safe Mode") export CUDA_VISIBLE_DEVICES=""; ARGS="$ARGS --cpu" ;;
esac

python main.py $ARGS &
PID=$!
sleep 10
if ! kill -0 $PID 2>/dev/null; then
  git reset --hard $(cat "$BASE/.last_good")
  zenity --error --text="ComfyUI crashed. Rolled back to last good state."
  exit 1
fi
wait $PID
EOF
chmod +x "$INSTALL_PATH/safe_launcher.sh"

# 9️⃣ Создание обычного launcher.sh
cat > "$INSTALL_PATH/launcher.sh" <<'EOF'
#!/usr/bin/env bash
"$HOME/ComfyUI-Desktop/safe_launcher.sh"
EOF
chmod +x "$INSTALL_PATH/launcher.sh"

# 10️⃣ Создание GUI Installer (PyQt6 stub)
mkdir -p "$INSTALL_PATH/gui"
cat > "$INSTALL_PATH/gui/installer_gui.py" <<'EOF'
from PyQt6.QtWidgets import QApplication, QWidget, QVBoxLayout, QPushButton, QTextEdit, QProgressBar, QLabel
import subprocess, sys

class Installer(QWidget):
    def __init__(self):
        super().__init__()
        self.setWindowTitle("ComfyUI Desktop Installer")
        self.resize(500,400)

        self.log = QTextEdit(); self.log.setReadOnly(True)
        self.progress = QProgressBar()
        self.btn = QPushButton("Install & Launch")
        self.btn.clicked.connect(self.install)

        layout = QVBoxLayout()
        layout.addWidget(QLabel("ComfyUI Desktop Installer"))
        layout.addWidget(self.progress)
        layout.addWidget(self.log)
        layout.addWidget(self.btn)
        self.setLayout(layout)

    def install(self):
        self.log.append("Running full installer...")
        self.progress.setValue(10)
        subprocess.Popen(["bash", "installer_full.sh"], cwd=".")

app = QApplication(sys.argv)
w = Installer()
w.show()
sys.exit(app.exec())
EOF

# 11️⃣ Создание AppRun для AppImage
mkdir -p "$INSTALL_PATH/AppImage/AppDir"
cat > "$INSTALL_PATH/AppImage/AppDir/AppRun" <<'EOF'
#!/usr/bin/env bash
HERE="$(dirname "$(readlink -f "$0")")"
exec "$HERE/../../launcher.sh"
EOF
chmod +x "$INSTALL_PATH/AppImage/AppDir/AppRun"

# 12️⃣ Создание README, LICENSE, VERSION
echo "# ComfyUI Desktop" > "$INSTALL_PATH/README.md"
echo "MIT License" > "$INSTALL_PATH/LICENSE"
echo "1.0.0" > "$INSTALL_PATH/VERSION"

# 13️⃣ Завершение установки
zenity --info --title="$APPNAME" --text="Installation complete!\nYou can launch ComfyUI from the launcher or AppImage."
echo "=== $APPNAME FINISHED ==="

