if test -z "$TOP"
then
    echo "Must set TOP env var to find app build directory"
    exit 1
fi
if test -z "$GMIDEVICE"
then
    echo "Must set GMIDEVICE env var to define the target device"
    exit 1
fi
if test -z "$GMICERTIFICATE"
then
    echo "Must set GMICERTIFICATE env var to define the app certificate"
    exit 1
fi
if test -z "$GMIPROVISIONING"
then
    echo "Must set GMIPROVISIONING env var to define the provisioning profile"
    exit 1
fi

mkdir -p $TOP/build/gmi

gmibuildtool \
   --app-name "Contacts" \
   --app-version "v3.2" \
   --output $TOP/build/contacts.ipa \
   --program-files $TOP/build/appdir \
   --icons resources/ios/icons \
   --storyboard resources/ios/LaunchScreen.storyboard \
   --bundle-id "com.fourjs.contacts" \
   --device "$GMIDEVICE" \
   --certificate "$GMICERTIFICATE" \
   --provisioning "$GMIPROVISIONING"

