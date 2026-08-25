package io.crates.keyring

import android.content.Context

/** JNI entrypoint supplied by android-native-keyring-store. */
class Keyring {
    companion object {
        external fun initializeNdkContext(context: Context)
    }
}
