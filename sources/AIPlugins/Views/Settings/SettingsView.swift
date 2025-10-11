import SwiftUI

struct SettingsView: View {
    @ObservedObject var settings: AppSettings

    var body: some View {
        Form {
            Section(header: Text(NSLocalizedString("api_settings", bundle: .aiPlugins, comment: ""))) {
                TextField("Provider", text: $settings.apiProvider)
                TextField("API Base URL", text: $settings.apiBaseURL)
                SecureField("API Key", text: $settings.apiKey)
            }

            Section(header: Text(NSLocalizedString("model", bundle: .aiPlugins, comment: ""))) {
                TextField("Default Model", text: $settings.defaultModel)
            }

            Section(header: Text(NSLocalizedString("general_settings", bundle: .aiPlugins, comment: ""))) {
                TextField("Plugin Directory", text: $settings.pluginDirectory)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}
