//
//  SidebarProjectList.swift
//  MultiGen
//
//  Created by Codex on 2025/02/14.
//

import SwiftUI

struct SidebarProjectList: View {
    @Binding var selection: SidebarItem

    var body: some View {
        List(selection: $selection) {
            ForEach(SidebarItem.primaryItems) { item in
                Label(item.title, systemImage: item.icon)
                    .tag(item)
            }
            Section("资料库") {
                ForEach(SidebarItem.libraryItems) { item in
                    Label(item.title, systemImage: item.icon)
                        .tag(item)
                }
            }
        }
        .listStyle(.sidebar)
    }
}
