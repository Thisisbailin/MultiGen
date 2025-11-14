//
//  MultiGenApp.swift
//  MultiGen
//
//  Created by Joe on 2025/11/12.
//

import SwiftUI

@main
struct MultiGenApp: App {
    @StateObject private var dependencies = AppDependencies.live()
    @StateObject private var scriptStore = ScriptStore()
    @StateObject private var storyboardStore = StoryboardStore()
    @StateObject private var promptLibraryStore = PromptLibraryStore()
    @StateObject private var navigationStore = NavigationStore()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(dependencies)
                .environmentObject(dependencies.configuration)
                .environmentObject(scriptStore)
                .environmentObject(storyboardStore)
                .environmentObject(promptLibraryStore)
                .environmentObject(navigationStore)
        }
    }
}
