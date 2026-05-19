# Visualization Framework Specification

## 1. Overview
Defines the integration of **VTK** and **Qt** for 2D/3D medical visualization, ensuring hardware-accelerated rendering on both x86 and QCS8550 platforms.

## 2. Architecture Stack

```mermaid
graph TD
    A[Application Logic] --> B[Qt Widgets/QML]
    B --> C[VTK Rendering Pipeline]
    C --> D[OpenGL/Vulkan Backend]
    D --> E[GPU Driver (Mesa/Adreno)]
    E --> F[Display Controller]
```

## 3. Component Configuration

### 3.1 VTK Build Flags
```bash
cmake -D CMAKE_BUILD_TYPE=Release \
      -D BUILD_SHARED_LIBS=OFF \
      -D VTK_GROUP_ENABLE_Rendering=YES \
      -D VTK_GROUP_ENABLE_Imaging=YES \
      -D VTK_OPENGL_HAS_EGL=YES \        # Critical for embedded ARM
      -D VTK_USE_X=OFF \                 # No X11 dependency (Wayland only)
      -D VTK_QT_VERSION=6 \
      -D Module_vtkGUISupportQt=ON \
      -D Module_vtkRenderingOpenGL2=ON \
      -D Module_vtkVolumeRendering=ON \
      ..
```

### 3.2 Qt Configuration
- **Version**: 6.5.2 LTS
- **Modules**: `QtWidgets`, `QtOpenGL`, `QtQuick3D`
- **Backend**: EGLFS (Embedded Linux Framebuffer) for headless operation.

## 4. Rendering Pipeline Optimization

### 4.1 Volume Rendering Strategies
- **Ray Casting**: Use GPU-based ray casting for CT/MRI volumes.
- **Level of Detail (LOD)**: Dynamically reduce resolution during interaction (rotate/zoom).
- **Texture Compression**: Use BC7/ASTC compression to reduce VRAM usage.

### 4.2 Multi-View Layouts
- Support synchronized cursors across axial, sagittal, coronal views.
- Implement "crosshair" linking using VTK observers:
  ```cpp
  vtkSmartPointer<vtkObserver> observer = vtkSmartPointer<vtkObserver>::New();
  sliceWidget->GetInteractorStyle()->AddObserver(vtkCommand::InteractionEvent, observer);
  ```

## 5. Performance Benchmarks

| Scenario | Resolution | FPS (x86 RTX 3060) | FPS (QCS8550 Adreno) | Target |
|----------|------------|--------------------|----------------------|--------|
| 2D Scroll (CT) | 512x512 | 60 FPS | 60 FPS | > 30 FPS |
| 3D Rotation (Bone) | 256³ voxels | 45 FPS | 28 FPS | > 24 FPS |
| MPR Reconstruction | 3 Views | 30 FPS | 22 FPS | > 20 FPS |
| Volume Ray Cast | 512³ voxels | 15 FPS | 8 FPS | > 10 FPS |

## 6. Thread Isolation Strategy
- **Render Thread**: Dedicated high-priority thread for OpenGL context.
- **Data Loading Thread**: Background thread for DICOM decompression.
- **UI Thread**: Main thread for user input; never block > 16ms.

## 7. References
- [VTK User Guide](https://vtk.org/documentation/)
- [Qt OpenGL Documentation](https://doc.qt.io/qt-6/qtopengl-index.html)
