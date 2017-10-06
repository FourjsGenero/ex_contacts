if test -z "$TOP"
then
    echo "Must set TOP env var to find app build directory"
    exit 1
fi

gma_app_output_dir=$TOP/build/gma
mkdir -p $gma_app_output_dir

gmabuildtool build \
    --android-sdk $ANDROID_SDK_ROOT \
    --clean \
    --build-force-scaffold-update --build-quietly \
    --build-output-apk-name contacts \
    --build-apk-outputs $gma_app_output_dir \
    --build-app-genero-program $TOP/build/appdir \
    --build-app-permissions android.permission.INTERNET,android.permission.ACCESS_NETWORK_STATE,android.permission.CHANGE_NETWORK_STATE,android.permission.ACCESS_WIFI_STATE,android.permission.ACCESS_COARSE_LOCATION,android.permission.ACCESS_FINE_LOCATION,android.permission.READ_EXTERNAL_STORAGE,android.permission.WRITE_EXTERNAL_STORAGE \
    --build-app-name Contacts \
    --build-app-package-name com.fourjs.contacts \
    --build-app-version-code 3010 \
    --build-app-version-name "3.1" \
    --build-mode release \
    --build-app-icon-mdpi   resources/android/icons/dbsync_contacts_48x48.png \
    --build-app-icon-hdpi   resources/android/icons/dbsync_contacts_72x72.png \
    --build-app-icon-xhdpi  resources/android/icons/dbsync_contacts_96x96.png \
    --build-app-icon-xxhdpi resources/android/icons/dbsync_contacts_144x144.png \
    --build-app-colors "#F44336,#B71C1C,#EF9A9A,#FFFFFF"

