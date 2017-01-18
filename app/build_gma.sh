if test -z "$TOP"
then
    echo "Must set TOP env var to find app build directory"
    exit 1
fi
if test -z "$GMASCAFFOLD"
then
    echo "Must set GMASCAFFOLD env var to find GMA project directory"
    exit 1
fi
#    --build-app-permissions android.permission.INTERNET,android.permission.ACCESS_NETWORK_STATE,android.permission.CHANGE_NETWORK_STATE,android.permission.ACCESS_WIFI_STATE,android.permission.WRITE_EXTERNAL_STORAGE,android.permission.MOUNT_FORMAT_FILESYSTEMS,android.permission.ACCESS_FINE_LOCATION \

mkdir -p $TOP/build/gma

gmabuildtool build \
    --android-sdk $ANDROID_HOME \
    --clean \
    --build-output-apk-name contacts \
    --build-apk-outputs $TOP/build/gma \
    --build-app-genero-program $TOP/build/appdir \
    --build-app-permissions android.permission.INTERNET,android.permission.ACCESS_NETWORK_STATE,android.permission.CHANGE_NETWORK_STATE,android.permission.ACCESS_WIFI_STATE,android.permission.ACCESS_COARSE_LOCATION,android.permission.ACCESS_FINE_LOCATION,android.permission.READ_EXTERNAL_STORAGE \
    --build-project $GMASCAFFOLD \
    --build-app-name Contacts \
    --build-app-package-name com.fourjs.contacts \
    --build-app-version-code 3010 \
    --build-app-version-name "3.1" \
    --build-mode release \
    --build-types arm,x86 \
    --build-app-icon-mdpi   resources/android/icons/anonymous_48x48.png \
    --build-app-icon-hdpi   resources/android/icons/anonymous_72x72.png \
    --build-app-icon-xhdpi  resources/android/icons/anonymous_96x96.png \
    --build-app-icon-xxhdpi resources/android/icons/anonymous_144x144.png \
    --build-app-colors "#F44336,#B71C1C,#EF9A9A,#FFFFFF"

