import Foundation

struct L10n {
    let language: AppLanguage

    // MARK: - Tabs

    var tabLive: String { t(en: "Live", zh: "拍摄", es: "En vivo") }
    var tabGallery: String { t(en: "Gallery", zh: "相册", es: "Galería") }
    var tabStudio: String { t(en: "Studio", zh: "工作室", es: "Estudio") }
    var tabSettings: String { t(en: "Settings", zh: "设置", es: "Ajustes") }

    // MARK: - Settings screen

    var settingsTitle: String { t(en: "Settings", zh: "设置", es: "Ajustes") }
    var settingsLanguage: String { t(en: "Language", zh: "语言", es: "Idioma") }
    var settingsColorTheme: String { t(en: "Color theme", zh: "色调", es: "Tema de color") }
    var settingsFooter: String {
        t(
            en: "Appearance applies to Gallery, Studio, and the sound editor.",
            zh: "外观会应用于相册、工作室与声音编辑界面。",
            es: "El aspecto se aplica a Galería, Estudio y el editor de sonido."
        )
    }

    func themeName(_ theme: PawShotColorTheme) -> String {
        switch theme {
        case .rose: return t(en: "Rose", zh: "玫瑰粉", es: "Rosa")
        case .ocean: return t(en: "Ocean", zh: "海洋蓝", es: "Océano")
        case .forest: return t(en: "Forest", zh: "森林绿", es: "Bosque")
        case .sunset: return t(en: "Sunset", zh: "日落橙", es: "Atardecer")
        case .lilac: return t(en: "Lilac", zh: "淡紫", es: "Lila")
        }
    }

    // MARK: - Camera

    var scanningForDog: String { t(en: "Looking for a dog’s face…", zh: "寻找狗狗正脸…", es: "Buscando el rostro del perro…") }
    var wakingCamera: String { t(en: "Starting camera and AI…", zh: "唤醒相机与 AI 引擎…", es: "Iniciando cámara e IA…") }
    var aiAuto: String { "AI AUTO" }
    var attraction: String { t(en: "Attraction", zh: "吸引", es: "Atracción") }
    var attractionDay: String { t(en: "DAY", zh: "日间", es: "DÍA") }
    var attractionNight: String { t(en: "NIGHT", zh: "夜间", es: "NOCHE") }
    var attractionOn: String { t(en: "ON", zh: "常亮", es: "ON") }
    var flash: String { t(en: "FLASH", zh: "闪光", es: "FLASH") }
    var shutterStart: String { t(en: "START", zh: "开始", es: "INICIO") }
    var faceLocked: String { t(en: "LOCKED", zh: "已锁定", es: "FIJADO") }

    // MARK: - Gallery

    var gallerySelectPhotosNav: String { t(en: "Select photos", zh: "选择照片", es: "Seleccionar fotos") }
    var galleryClose: String { t(en: "Close", zh: "关闭", es: "Cerrar") }
    var galleryDone: String { t(en: "Done", zh: "完成", es: "Listo") }
    var gallerySelect: String { t(en: "Select", zh: "选择", es: "Seleccionar") }

    func gallerySelectedCount(_ n: Int) -> String {
        t(en: "\(n) selected", zh: "已选 \(n) 张", es: "\(n) seleccionadas")
    }

    var smartCuration: String { t(en: "SMART CURATION", zh: "智能精选", es: "CURACIÓN INTELIGENTE") }
    var galleryHeading: String { tabGallery }
    var gallerySubtitle: String {
        t(en: "Your pet’s best moments, curated by AI", zh: "由 AI 精选的宠物高光时刻", es: "Los mejores momentos de tu mascota, con IA")
    }
    var galleryEmptyTitle: String { t(en: "No photos yet", zh: "暂无拍摄照片", es: "Aún no hay fotos") }
    var galleryEmptySubtitle: String {
        t(en: "Photos you take will appear here", zh: "拍几张宠物照后会显示在这里", es: "Las fotos que tomes aparecerán aquí")
    }

    // MARK: - Studio / sounds

    var studioDone: String { galleryDone }
    var saveRecordingTitle: String { t(en: "Save recording", zh: "保存录音", es: "Guardar grabación") }
    var namePlaceholder: String { t(en: "Name", zh: "输入名字", es: "Nombre") }
    var save: String { t(en: "Save", zh: "保存", es: "Guardar") }
    var discard: String { t(en: "Discard", zh: "丢弃", es: "Descartar") }
    var recordVoiceTitle: String { t(en: "Record Voice", zh: "录制声音", es: "Grabar voz") }
    var recordVoiceSubtitle: String {
        t(
            en: "Capture a “Good Boy!” or a custom whistle",
            zh: "录一句「好乖」或自定义哨音",
            es: "Graba un «¡Buen chico!» o un silbido propio"
        )
    }
    var recording: String { t(en: "Recording…", zh: "录音中…", es: "Grabando…") }
    var stop: String { t(en: "Stop", zh: "停止", es: "Detener") }
    var record: String { t(en: "Record", zh: "录制", es: "Grabar") }
    var micPermissionNeeded: String { t(en: "Microphone access needed", zh: "需要麦克风权限", es: "Se necesita acceso al micrófono") }
    var library: String { t(en: "Library", zh: "声音库", es: "Biblioteca") }
    var allSounds: String { t(en: "All Sounds", zh: "全部声音", es: "Todos los sonidos") }
    var soundsEmpty: String { t(en: "No sounds yet — tap Record", zh: "暂无声音，请录制", es: "Sin sonidos — pulsa Grabar") }
    var soundSystem: String { t(en: "Built-in", zh: "系统内置", es: "Integrado") }
    var soundCustom: String { t(en: "My recording", zh: "我的录音", es: "Mi grabación") }
    var a11ySoundInRotation: String { t(en: "In shuffle rotation", zh: "已加入随机播放", es: "En rotación aleatoria") }
    var a11ySoundNotInRotation: String { t(en: "Not in shuffle rotation", zh: "未加入随机播放", es: "Fuera de rotación aleatoria") }

    // MARK: - Audio editor

    var analyzingWaveform: String { t(en: "Analyzing audio…", zh: "正在分析声纹…", es: "Analizando audio…") }
    var editSound: String { t(en: "Edit Sound", zh: "编辑声音", es: "Editar sonido") }
    var backToStudio: String { tabStudio }
    var durationHighFidelity: String {
        t(en: "Duration • High fidelity", zh: "时长 • 高保真", es: "Duración • Alta fidelidad")
    }
    var volumeBoost: String { t(en: "Volume Boost", zh: "音量增强", es: "Refuerzo de volumen") }
    var volumeBoostMax: String { t(en: "Boost up to 150%", zh: "音量增强 (最大 150%)", es: "Hasta 150 % de refuerzo") }
    var volumeStandard: String { t(en: "Standard level", zh: "标准音量", es: "Nivel estándar") }
    var volumeReduced: String { t(en: "Reduced level", zh: "音量衰减", es: "Nivel reducido") }
    var preview: String { t(en: "Preview", zh: "试听", es: "Vista previa") }
    func trimmedSoundName(_ base: String) -> String {
        let suffix = t(en: " (trimmed)", zh: "（剪辑）", es: " (recorte)")
        return base + suffix
    }

    private func t(en: String, zh: String, es: String) -> String {
        switch language {
        case .english: return en
        case .chinese: return zh
        case .spanish: return es
        }
    }
}
