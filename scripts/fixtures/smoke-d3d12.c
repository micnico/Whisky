#define COBJMACROS
#define INITGUID
#include <windows.h>
#include <d3d12.h>

int main(void)
{
    ID3D12Device *device = NULL;
    HRESULT result = D3D12CreateDevice(NULL, D3D_FEATURE_LEVEL_11_0,
                                       &IID_ID3D12Device, (void **)&device);

    if (device) ID3D12Device_Release(device);
    return FAILED(result);
}
