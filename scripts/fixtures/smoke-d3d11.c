#define COBJMACROS
#include <windows.h>
#include <d3d11.h>

int main(void)
{
    ID3D11Device *device = NULL;
    ID3D11DeviceContext *context = NULL;
    HRESULT result = D3D11CreateDevice(NULL, D3D_DRIVER_TYPE_HARDWARE, NULL, 0,
                                       NULL, 0, D3D11_SDK_VERSION, &device, NULL, &context);

    if (context) ID3D11DeviceContext_Release(context);
    if (device) ID3D11Device_Release(device);
    return FAILED(result);
}
