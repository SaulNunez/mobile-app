package io.rebble.cobble.bridges.common

import io.rebble.cobble.bridges.FlutterBridge
import io.rebble.cobble.bridges.ui.BridgeLifecycleController
import io.rebble.cobble.middleware.AppLogController
import io.rebble.cobble.pigeons.Pigeons
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Job
import kotlinx.coroutines.flow.collect
import kotlinx.coroutines.launch
import timber.log.Timber
import javax.inject.Inject

class AppLogFlutterBridge @Inject constructor(
        bridgeLifecycleController: BridgeLifecycleController,
        private val coroutineScope: CoroutineScope,
        private val appLogController: AppLogController
) : FlutterBridge, Pigeons.AppLogControl {
    private val callbacks = bridgeLifecycleController.createCallbacks(Pigeons::AppLogCallbacks)

    private var logsJob: Job? = null

    init {
        bridgeLifecycleController.setupControl(Pigeons.AppLogControl::setup, this)
    }

    override fun startSendingLogs() {
        stopSendingLogs()

        logsJob = coroutineScope.launch {
            appLogController.logs.collect {
                Timber.d("Received in pigeon '%s'", it.message.get())
                callbacks.onLogReceived(
                        Pigeons.AppLogEntry().apply {
                            uuid = it.uuid.get().toString()
                            timestamp = it.timestamp.get().toLong()
                            level = it.level.get().toLong()
                            lineNumber = it.lineNumber.get().toLong()
                            filename = it.filename.get()
                            message = it.message.get()
                        }
                ) {}
            }
        }
    }

    override fun stopSendingLogs() {
        logsJob?.cancel()
    }
}