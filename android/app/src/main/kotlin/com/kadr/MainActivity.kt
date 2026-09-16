package com.kadr

import android.content.ComponentName
import android.content.Intent
import android.content.pm.PackageManager
import android.content.pm.ShortcutInfo
import android.content.pm.ShortcutManager
import android.graphics.BitmapFactory
import android.graphics.drawable.Icon
import android.os.Build
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {

    companion object {
        private const val CHANNEL = "app_icon"

        /** id колеровки → activity-alias в манифесте. Ключи совпадают с AppIconService. */
        private val ICON_ALIASES = mapOf(
            "glow" to ".IconGlow",
            "ink" to ".IconInk",
            "graphite" to ".IconGraphite",
            "white" to ".IconWhite",
        )
        private const val DEFAULT_ICON = "glow"
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        migrateIconAliases()
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "setIcon" -> {
                        val id = call.argument<String>("id") ?: DEFAULT_ICON
                        if (!ICON_ALIASES.containsKey(id)) {
                            result.error("bad_icon", "Неизвестная иконка: $id", null)
                        } else {
                            applyIcon(id)
                            result.success(true)
                        }
                    }
                    "currentIcon" -> result.success(currentIcon())
                    "canPinShortcut" -> result.success(canPinShortcut())
                    "pinShortcut" -> {
                        val png = call.argument<ByteArray>("icon")
                        val label = call.argument<String>("label") ?: "Kadr"
                        if (png == null) {
                            result.error("no_icon", "Не передана картинка ярлыка", null)
                        } else {
                            result.success(pinShortcut(png, label))
                        }
                    }
                    else -> result.notImplemented()
                }
            }
    }

    /**
     * Включает alias выбранной колеровки и гасит остальные.
     *
     * Сначала включаем нужный, потом выключаем прочие: при обратном порядке
     * остаётся момент, когда не включён ни один LAUNCHER-компонент, и часть
     * лаунчеров успевает убрать ярлык с рабочего стола.
     *
     * DONT_KILL_APP — иначе система убьёт процесс прямо во время работы.
     */
    private fun applyIcon(id: String) {
        val target = ICON_ALIASES[id] ?: return
        setAliasEnabled(target, true)
        ICON_ALIASES.values.filter { it != target }.forEach { setAliasEnabled(it, false) }
    }

    /**
     * Основное лого сменилось (2026-09-16): в манифесте теперь включён IconGlow,
     * а IconInk выключен. Кто уже выбирал иконку сам, у того старые alias'ы стоят
     * в явном состоянии, а новый — в DEFAULT, то есть включён по манифесту: в
     * лаунчере оказалось бы два ярлыка. Гасим новый, выбор человека остаётся.
     */
    private fun migrateIconAliases() {
        val glow = ICON_ALIASES.getValue(DEFAULT_ICON)
        if (aliasState(glow) != PackageManager.COMPONENT_ENABLED_STATE_DEFAULT) return
        val chosen = ICON_ALIASES.values.any {
            it != glow && aliasState(it) == PackageManager.COMPONENT_ENABLED_STATE_ENABLED
        }
        if (chosen) setAliasEnabled(glow, false)
    }

    private fun aliasState(alias: String): Int =
        packageManager.getComponentEnabledSetting(ComponentName(packageName, packageName + alias))

    private fun setAliasEnabled(alias: String, enabled: Boolean) {
        val state = if (enabled) PackageManager.COMPONENT_ENABLED_STATE_ENABLED
        else PackageManager.COMPONENT_ENABLED_STATE_DISABLED
        packageManager.setComponentEnabledSetting(
            ComponentName(packageName, packageName + alias),
            state,
            PackageManager.DONT_KILL_APP,
        )
    }

    /**
     * Поддерживает ли лаунчер закрепление ярлыка.
     *
     * Закрепление появилось в Android 8 (API 26), а minSdk у нас 24 — на 24/25
     * фича недоступна и её пункт не показываем. Часть лаунчеров умеет говорить
     * «не поддерживаю» и на новых версиях.
     */
    private fun canPinShortcut(): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return false
        val sm = getSystemService(ShortcutManager::class.java) ?: return false
        return sm.isRequestPinShortcutSupported
    }

    /**
     * Кладёт на рабочий стол ярлык с произвольной картинкой.
     *
     * Это ДОПОЛНИТЕЛЬНЫЙ ярлык, а не замена иконки приложения: произвольный
     * bitmap Android разрешает только ярлыкам, launcher-иконка обязана лежать
     * в APK (для неё есть activity-alias выше).
     *
     * id постоянный: повторное закрепление обновит картинку уже стоящего ярлыка,
     * а не насыплет копий.
     */
    private fun pinShortcut(png: ByteArray, label: String): Boolean {
        if (!canPinShortcut()) return false
        val sm = getSystemService(ShortcutManager::class.java) ?: return false
        val bmp = BitmapFactory.decodeByteArray(png, 0, png.size) ?: return false
        val intent = Intent(this, MainActivity::class.java).apply {
            action = Intent.ACTION_MAIN
            addCategory(Intent.CATEGORY_LAUNCHER)
        }
        val info = ShortcutInfo.Builder(this, "kadr_custom_icon")
            .setShortLabel(label)
            .setLongLabel(label)
            .setIcon(Icon.createWithAdaptiveBitmap(bmp))
            .setIntent(intent)
            .build()
        // Часть лаунчеров обновляет уже закреплённый ярлык только через updateShortcuts.
        sm.updateShortcuts(listOf(info))
        return sm.requestPinShortcut(info, null)
    }

    /** Какая колеровка включена сейчас: источник истины — система, а не наши настройки. */
    private fun currentIcon(): String {
        // Явный выбор важнее манифеста: сначала ищем включённый руками alias.
        for ((id, alias) in ICON_ALIASES) {
            if (aliasState(alias) == PackageManager.COMPONENT_ENABLED_STATE_ENABLED) return id
        }
        // Выбора не было: работает манифест, а там включён только дефолтный alias.
        return DEFAULT_ICON
    }
}
