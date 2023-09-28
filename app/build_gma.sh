if test -z "$ANDROID_HOME"
then
    echo "Must set ANDROID_HOME env var"
    exit 1
fi
if test -z "$JAVA_HOME"
then
    echo "Must set JAVA_HOME env var"
    exit 1
fi
if test -z "$TOP"
then
    echo "Must set TOP env var to find app build directory"
    exit 1
fi
if test -n "$FGLGBCDIR"
then
    gbc_version="--build-gbc-runtime $FGLGBCDIR"
fi

permissions="
android.permission.CAMERA,\
android.permission.INTERNET,\
android.permission.ACCESS_NETWORK_STATE,\
android.permission.CHANGE_NETWORK_STATE,\
android.permission.ACCESS_WIFI_STATE,\
android.permission.ACCESS_COARSE_LOCATION,\
android.permission.ACCESS_FINE_LOCATION,\
android.permission.READ_EXTERNAL_STORAGE,\
android.permission.WRITE_EXTERNAL_STORAGE\
"

appdir=/tmp/appdir_contacts

rootdir=/tmp/build_contacts
rm -rf $rootdir
mkdir -p $rootdir

outdir=/tmp

gmabuildtool build \
    --android-sdk $ANDROID_HOME \
    --clean \
    $gbc_version \
    --build-apk-outputs $outdir \
    --build-output-apk-name contacts \
    --root-path $rootdir \
    --main-app-path $appdir/main.42m \
    --build-app-permissions "$permissions"\
    --build-app-name Contacts \
    --build-app-package-name com.fourjs.contacts \
    --build-app-version-code 3020 \
    --build-app-version-name "3.2" \
    --build-mode release \
    --build-app-icon-mdpi   resources/android/icons/dbsync_contacts_48x48.png \
    --build-app-icon-hdpi   resources/android/icons/dbsync_contacts_72x72.png \
    --build-app-icon-xhdpi  resources/android/icons/dbsync_contacts_96x96.png \
    --build-app-icon-xxhdpi resources/android/icons/dbsync_contacts_144x144.png \
    --build-app-colors "#F44336,#B71C1C,#EF9A9A,#FFFFFF"

