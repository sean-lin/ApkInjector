defmodule ManifestTest do
  use ExUnit.Case

  @xml """ 
<?xml version="1.0" encoding="utf-8" standalone="no"?>
    <manifest xmlns:android="http://schemas.android.com/apk/res/android" package="com.ejoy.injector" platformBuildVersionCode="23" platformBuildVersionName="6.0-2704002">
    <uses-permission
    android:name="android.permission.WRITE_EXTERNAL_STORAGE"
    android:maxSdkVersion="18" />
    <application android:allowBackup="true" android:debuggable="true" android:icon="@mipmap/ic_launcher" android:label="@string/app_name" android:supportsRtl="true" android:theme="@style/AppTheme">
    <activity android:name="com.ejoy.injector.MainActivity">
    <intent-filter>
    <action android:name="android.intent.action.MAIN"/>
    <category android:name="android.intent.category.LAUNCHER"/>
    </intent-filter>
    </activity>
    </application>
    </manifest>
  """

  test "load_string" do
    manifest = Injector.AndroidManifest.string(@xml)
    assert manifest.main_activity_name == 'com.ejoy.injector.MainActivity'
    assert :sets.to_list(manifest.uses_permission) == ['android.permission.WRITE_EXTERNAL_STORAGE']

    assert Injector.AndroidManifest.render(manifest)
  end
end
