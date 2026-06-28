import SwiftUI

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    
    // После сброса — нужно сообщить главному экрану чтобы он перезагрузился
    let onReset: () -> Void

    @State private var showResetConfirmation = false
    
    // Тумблер вибрации — читаем напрямую из StorageService
    // @State чтобы UI обновлялся при изменении
    @Bindable private var storage = StorageService.shared
    
    var body: some View {
        NavigationStack {
            Form {
                
                // MARK: Общие
                
                Section {
                    // Тумблер вибрации
                    Toggle(isOn: $storage.hapticsEnabled) {
                        HStack {
                            Image(systemName: "iphone.radiowaves.left.and.right")
                                .foregroundColor(.purple)
                                .frame(width: 28)
                            Text("Вибрация")
                        }
                    }
                } header: {
                    Text("Общие")
                } footer: {
                    Text("Лёгкая тактильная отдача при свайпе.")
                }
                
                // MARK: Будущие функции
    
                Section {
                    HStack {
                        Image(systemName: "bell.fill")
                            .foregroundColor(.orange)
                            .frame(width: 28)
                        Text("Уведомления")
                        Spacer()
                        Text("Скоро")
                            .font(.system(size: 14))
                            .foregroundColor(.secondary)
                    }
                    .opacity(0.5)
                    
                    HStack {
                        Image(systemName: "lock.shield.fill")
                            .foregroundColor(.purple)
                            .frame(width: 28)
                        Text("Блокировка приложений")
                        Spacer()
                        Text("Скоро")
                            .font(.system(size: 14))
                            .foregroundColor(.secondary)
                    }
                    .opacity(0.5)
                } header: {
                    Text("Будущие функции")
                } footer: {
                    Text("Эти функции появятся в следующих обновлениях.")
                }
                
                // MARK: Дебаг удалить перед публикацией
                #if DEBUG
                Section {
                    Button {
                        showResetConfirmation = true
                    } label: {
                        HStack {
                            Image(systemName: "arrow.counterclockwise")
                                .foregroundColor(.red)
                                .frame(width: 28)
                            Text("Сбросить все данные")
                                .foregroundColor(.red)
                        }
                    }
                } header: {
                    Text("Для разработчика")
                } footer: {
                    Text("Удалит весь прогресс, статистику и снова покажет онбординг. Эта секция будет удалена перед публикацией.")
                }
                #endif
                
                // MARK: О приложении
                
                Section {
                    HStack {
                        Image(systemName: "info.circle.fill")
                            .foregroundColor(.blue)
                            .frame(width: 28)
                        Text("Версия")
                        Spacer()
                        Text(appVersion)
                            .foregroundColor(.secondary)
                    }
                    
                    HStack {
                        Image(systemName: "hand.raised.fill")
                            .foregroundColor(.green)
                            .frame(width: 28)
                        Text("Политика конфиденциальности")
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.system(size: 13))
                            .foregroundColor(.secondary)
                    }
                } header: {
                    Text("О приложении")
                }
                
                // MARK: Подвал
                
                Section {
                    VStack(spacing: 8) {
                        Text("Photo Sorting")
                            .font(.system(size: 14, weight: .semibold))
                        Text("Сделано с заботой о вашей галерее")
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .listRowBackground(Color.clear)
                }
            }
            .navigationTitle("Настройки")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Готово") { dismiss() }
                }
            }
            .alert("Сбросить все данные?", isPresented: $showResetConfirmation) {
                Button("Отмена", role: .cancel) {}
                Button("Сбросить", role: .destructive) {
                    storage.resetAll()
                    onReset()
                    dismiss()
                }
            } message: {
                Text("Это действие нельзя отменить. Вся статистика и история обработанных фото будут удалены.")
            }
        }
    }
    
    // MARK: - Версия из Info.plist
    
    private var appVersion: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "\(version) (\(build))"
    }
}

#Preview {
    SettingsView(onReset: {})
}
