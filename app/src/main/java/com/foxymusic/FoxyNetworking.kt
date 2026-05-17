package com.foxymusic

import okhttp3.OkHttpClient
import java.net.InetSocketAddress
import java.net.Proxy
import java.util.concurrent.TimeUnit

object FoxyNetworking {

    fun applyProxy(builder: OkHttpClient.Builder): OkHttpClient.Builder {
        val s = FoxySettings.state.value
        if (!s.proxyEnabled) return builder
        val ep = s.proxyEndpoint.trim()
        if (ep.isBlank()) return builder
        val parts = ep.split(":", limit = 2).map { it.trim() }
        if (parts.size != 2) return builder
        val port = parts[1].toIntOrNull() ?: return builder
        val host = parts[0].ifBlank { return builder }
        return builder.proxy(Proxy(Proxy.Type.HTTP, InetSocketAddress(host, port)))
    }

    fun streamingClient(): OkHttpClient =
        OkHttpClient.Builder()
            .retryOnConnectionFailure(true)
            .connectTimeout(8, TimeUnit.SECONDS)
            .readTimeout(16, TimeUnit.SECONDS)
            .let { applyProxy(it) }
            .build()
}
