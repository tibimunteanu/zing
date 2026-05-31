//========================================================================
// GLFW 3.4 native access header, trimmed for this Vulkan-only fork
//========================================================================

#pragma once

#ifdef __cplusplus
extern "C" {
#endif

#if !defined(GLFW_NATIVE_INCLUDE_NONE)
 #if defined(GLFW_EXPOSE_NATIVE_WIN32)
  #include <windows.h>
 #endif
 #if defined(GLFW_EXPOSE_NATIVE_COCOA)
  #if defined(__OBJC__)
   #import <Cocoa/Cocoa.h>
  #else
   #include <ApplicationServices/ApplicationServices.h>
   typedef void* id;
  #endif
 #endif
 #if defined(GLFW_EXPOSE_NATIVE_X11)
  #include <X11/Xlib.h>
  #include <X11/extensions/Xrandr.h>
 #endif
#endif

#if defined(GLFW_EXPOSE_NATIVE_WIN32)
GLFWAPI const char* glfwGetWin32Adapter(GLFWmonitor* monitor);
GLFWAPI const char* glfwGetWin32Monitor(GLFWmonitor* monitor);
GLFWAPI HWND glfwGetWin32Window(GLFWwindow* window);
#endif

#if defined(GLFW_EXPOSE_NATIVE_COCOA)
GLFWAPI CGDirectDisplayID glfwGetCocoaMonitor(GLFWmonitor* monitor);
GLFWAPI id glfwGetCocoaWindow(GLFWwindow* window);
GLFWAPI id glfwGetCocoaView(GLFWwindow* window);
#endif

#if defined(GLFW_EXPOSE_NATIVE_X11)
GLFWAPI Display* glfwGetX11Display(void);
GLFWAPI RRCrtc glfwGetX11Adapter(GLFWmonitor* monitor);
GLFWAPI RROutput glfwGetX11Monitor(GLFWmonitor* monitor);
GLFWAPI Window glfwGetX11Window(GLFWwindow* window);
GLFWAPI void glfwSetX11SelectionString(const char* string);
GLFWAPI const char* glfwGetX11SelectionString(void);
#endif

#ifdef __cplusplus
}
#endif
