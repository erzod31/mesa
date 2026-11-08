#include "flutter_window.h"

#include <optional>
#include <shellapi.h>
#include <flutter/standard_method_codec.h>

#include "flutter/generated_plugin_registrant.h"

FlutterWindow::FlutterWindow(const flutter::DartProject& project)
    : project_(project) {}

FlutterWindow::~FlutterWindow() {}

bool FlutterWindow::OnCreate() {
  if (!Win32Window::OnCreate()) {
    return false;
  }

  RECT frame = GetClientArea();

  // The size here must match the window dimensions to avoid unnecessary surface
  // creation / destruction in the startup path.
  flutter_controller_ = std::make_unique<flutter::FlutterViewController>(
      frame.right - frame.left, frame.bottom - frame.top, project_);
  // Ensure that basic setup of the controller was successful.
  if (!flutter_controller_->engine() || !flutter_controller_->view()) {
    return false;
  }
  RegisterPlugins(flutter_controller_->engine());
  native_channel_ = std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
      flutter_controller_->engine()->messenger(), "mesa/native",
      &flutter::StandardMethodCodec::GetInstance());
  native_channel_->SetMethodCallHandler([this](const auto& call, auto result) {
    if (call.method_name() == "quitForUpdate") {
      result->Success();
      // Called only after the confirmed update handoff has been prepared.
      PostMessage(GetHandle(), WM_CLOSE, 0, 0);
    } else if (call.method_name() == "awake") {
      const auto* enabled = call.arguments() ? std::get_if<bool>(call.arguments()) : nullptr;
      SetThreadExecutionState(ES_CONTINUOUS | (enabled && *enabled ? ES_DISPLAY_REQUIRED : 0));
      result->Success();
    } else if (call.method_name() == "openUrl") {
      const auto* url = call.arguments() ? std::get_if<std::string>(call.arguments()) : nullptr;
      if (!url || url->rfind("https://", 0) != 0 || url->find_first_of("\r\n\t") != std::string::npos) {
        result->Error("url", "Enlace de fuente incorrecto.");
        return;
      }
      const int length = MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS, url->c_str(), -1, nullptr, 0);
      if (length <= 0) { result->Error("url", "Enlace incorrecto."); return; }
      std::wstring wide(length, L'\0');
      MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS, url->c_str(), -1, wide.data(), length);
      if (reinterpret_cast<INT_PTR>(ShellExecuteW(nullptr, L"open", wide.c_str(), nullptr, nullptr, SW_SHOWNORMAL)) <= 32) {
        result->Error("browser", "No se pudo abrir el navegador.");
      } else {
        result->Success();
      }
    } else if (call.method_name() == "initialShare") {
      result->Success();
    } else {
      result->NotImplemented();
    }
  });
  SetChildContent(flutter_controller_->view()->GetNativeWindow());

  flutter_controller_->engine()->SetNextFrameCallback([&]() {
    this->Show();
  });

  // Flutter can complete the first frame before the "show window" callback is
  // registered. The following call ensures a frame is pending to ensure the
  // window is shown. It is a no-op if the first frame hasn't completed yet.
  flutter_controller_->ForceRedraw();

  return true;
}

void FlutterWindow::OnDestroy() {
  SetThreadExecutionState(ES_CONTINUOUS);
  native_channel_.reset();
  if (flutter_controller_) {
    flutter_controller_ = nullptr;
  }

  Win32Window::OnDestroy();
}

LRESULT
FlutterWindow::MessageHandler(HWND hwnd, UINT const message,
                              WPARAM const wparam,
                              LPARAM const lparam) noexcept {
  // Give Flutter, including plugins, an opportunity to handle window messages.
  if (flutter_controller_) {
    std::optional<LRESULT> result =
        flutter_controller_->HandleTopLevelWindowProc(hwnd, message, wparam,
                                                      lparam);
    if (result) {
      return *result;
    }
  }

  switch (message) {
    case WM_FONTCHANGE:
      flutter_controller_->engine()->ReloadSystemFonts();
      break;
  }

  return Win32Window::MessageHandler(hwnd, message, wparam, lparam);
}
