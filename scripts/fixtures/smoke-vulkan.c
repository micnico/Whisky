#include <stdio.h>
#include <vulkan/vulkan.h>

int main(void)
{
    const char *extensions[] = { VK_KHR_PORTABILITY_ENUMERATION_EXTENSION_NAME };
    VkApplicationInfo application = {
        .sType = VK_STRUCTURE_TYPE_APPLICATION_INFO,
        .pApplicationName = "whisky-vulkan-smoke",
        .apiVersion = VK_API_VERSION_1_1,
    };
    VkInstanceCreateInfo create_info = {
        .sType = VK_STRUCTURE_TYPE_INSTANCE_CREATE_INFO,
        .flags = VK_INSTANCE_CREATE_ENUMERATE_PORTABILITY_BIT_KHR,
        .pApplicationInfo = &application,
        .enabledExtensionCount = 1,
        .ppEnabledExtensionNames = extensions,
    };
    VkInstance instance = VK_NULL_HANDLE;
    uint32_t device_count = 0;
    VkResult result = vkCreateInstance(&create_info, NULL, &instance);

    if (result != VK_SUCCESS) {
        fprintf(stderr, "vkCreateInstance failed: %d\n", result);
        return 1;
    }
    result = vkEnumeratePhysicalDevices(instance, &device_count, NULL);
    vkDestroyInstance(instance, NULL);
    if (result != VK_SUCCESS || device_count == 0) {
        fprintf(stderr, "vkEnumeratePhysicalDevices failed: %d, devices: %u\n",
                result, device_count);
        return 1;
    }
    printf("Vulkan devices: %u\n", device_count);
    return 0;
}
