// Starts an app's widget extension inside the app (new-website#643): the extension's sources
// build as a library target with its `@main` entry point renamed `swiftui_web_widgets_main`
// (`-Xfrontend -entry-point-function-name -Xfrontend swiftui_web_widgets_main`). An app without
// one links no such function: the weak reference is null and nothing runs.
#ifndef SWIFTUIWEB_WIDGET_LAUNCHER_H
#define SWIFTUIWEB_WIDGET_LAUNCHER_H

/// Runs the widget extension's entry point when the app has one; returns whether it did.
int swiftui_web_launch_widgets(void);

#endif
