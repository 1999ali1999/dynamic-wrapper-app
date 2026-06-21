#!/bin/bash

# 1. إعداد Flutter SDK
cd /home/vscode
if [ ! -d "flutter" ]; then
    git clone https://github.com/flutter/flutter.git -b stable
fi

# إضافة Flutter إلى مسارات النظام بشكل جذري ليعمل في Terminal
echo 'export PATH="$PATH:/home/vscode/flutter/bin"' >> ~/.bashrc
echo 'export PATH="$PATH:/home/vscode/flutter/bin"' >> ~/.profile

# 2. إعداد Android SDK
export ANDROID_HOME=/home/vscode/android-sdk
mkdir -p $ANDROID_HOME/cmdline-tools
cd $ANDROID_HOME/cmdline-tools

wget -q https://dl.google.com/android/repository/commandlinetools-linux-11479570_latest.zip -O cmdline-tools.zip
unzip -q cmdline-tools.zip
mv cmdline-tools latest
rm cmdline-tools.zip

# إضافة Android إلى مسارات النظام
echo 'export ANDROID_HOME="/home/vscode/android-sdk"' >> ~/.bashrc
echo 'export PATH="$PATH:$ANDROID_HOME/cmdline-tools/latest/bin:$ANDROID_HOME/platform-tools"' >> ~/.bashrc

# تطبيق المسارات على الجلسة الحالية لتنفيذ باقي الأوامر بنجاح
export PATH="$PATH:$ANDROID_HOME/cmdline-tools/latest/bin:$ANDROID_HOME/platform-tools:/home/vscode/flutter/bin"

# 3. التراخيص وأدوات البناء
yes | sdkmanager --licenses > /dev/null
sdkmanager "platform-tools" "platforms;android-34" "build-tools;34.0.0" > /dev/null

# 4. الربط النهائي وتهيئة بيئة Web
flutter config --android-sdk $ANDROID_HOME
flutter config --enable-web
flutter upgrade --force
flutter precache
