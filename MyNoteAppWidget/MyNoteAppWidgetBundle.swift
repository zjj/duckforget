//
//  MyNoteAppWidgetBundle.swift
//  MyNoteAppWidget
//
//  Created by jj.zhong on 19/2/2026.
//

import WidgetKit
import SwiftUI

@main
struct MyNoteAppWidgetBundle: WidgetBundle {
    var body: some Widget {
        MyNoteAppWidget()
        MyNoteAppWidgetLiveActivity()
        MyNoteAppWidgetControl()
    }
}
