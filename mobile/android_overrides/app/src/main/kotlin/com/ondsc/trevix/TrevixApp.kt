package com.ondsc.trevix

import android.app.Application

/** Inicia Firebase al arrancar el proceso (antes que el servicio que recibe los avisos con la app cerrada). */
class TrevixApp : Application() {
    override fun onCreate() {
        super.onCreate()
        Fcm.init(this)
    }
}
