//
//  MultiGenApp.swift
//  MultiGen
//
//  Created by Joe on 2025/11/12.
//

import SwiftUI

@main
struct MultiGenApp: App {
    @StateObject private var dependencies: AppDependencies
    @StateObject private var scriptStore: ScriptStore
    @StateObject private var storyboardStore: StoryboardStore
    @StateObject private var promptLibraryStore: PromptLibraryStore
    @StateObject private var imagingStore: ImagingStore
    @StateObject private var navigationStore: NavigationStore
    @StateObject private var actionCenter: AIActionCenter

    init() {
        let deps = AppDependencies.live()
        let script = ScriptStore()
        let storyboard = StoryboardStore()
        let prompt = PromptLibraryStore()
        let navigation = NavigationStore()
        _dependencies = StateObject(wrappedValue: deps)
        _scriptStore = StateObject(wrappedValue: script)
        _storyboardStore = StateObject(wrappedValue: storyboard)
        _promptLibraryStore = StateObject(wrappedValue: prompt)
        _imagingStore = StateObject(wrappedValue: ImagingStore())
        _navigationStore = StateObject(wrappedValue: navigation)
        let center = AIActionCenter(
            dependencies: deps,
            navigationStore: navigation
        )
        _actionCenter = StateObject(wrappedValue: center)
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(dependencies)
                .environmentObject(dependencies.configuration)
                .environmentObject(scriptStore)
                .environmentObject(storyboardStore)
                .environmentObject(promptLibraryStore)
                .environmentObject(imagingStore)
                .environmentObject(navigationStore)
                .environmentObject(actionCenter)
        }
        Settings {
            SettingsView()
                .environmentObject(dependencies)
                .environmentObject(actionCenter)
                .environmentObject(dependencies.configuration)
                .environmentObject(navigationStore)
        }
    }
}
