#ifndef ZING_MINIMAL_VULKAN_H
#define ZING_MINIMAL_VULKAN_H

#include <stdint.h>

#define VK_VERSION_1_0 1

typedef struct VkInstance_T* VkInstance;
typedef struct VkPhysicalDevice_T* VkPhysicalDevice;
typedef uint64_t VkSurfaceKHR;
typedef int32_t VkResult;
typedef struct VkAllocationCallbacks VkAllocationCallbacks;
typedef void (*PFN_vkVoidFunction)(void);
typedef PFN_vkVoidFunction (*PFN_vkGetInstanceProcAddr)(VkInstance instance, const char* pName);

#endif
