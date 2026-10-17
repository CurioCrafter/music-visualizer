//! Text + icons for the glass UI. Windows GDI draws them (grey-scale antialiased) into a screen-sized
//! mask, one RGBA channel per fade group; the GPU composite pass lays them over the glass.
//! Only re-rendered when the text itself changes, never per frame.

use windows::core::PCWSTR;
use windows::Win32::Foundation::{COLORREF, RECT};
use windows::Win32::Graphics::Gdi::*;

#[derive(Clone, Copy, PartialEq, Debug)]
pub enum Align {
    Left,
    Center,
    Right,
}

#[derive(Clone, PartialEq, Debug)]
pub struct TextItem {
    pub text: String,
    pub rect: [i32; 4], // x, y, w, h
    pub size: f32,      // px
    pub bold: bool,
    pub icon: bool, // Segoe Fluent Icons
    pub align: Align,
    pub channel: usize, // 0 buttons, 1 look name, 2 song, 3 panel/hint
}

fn wide(s: &str) -> Vec<u16> {
    s.encode_utf16().chain(std::iter::once(0)).collect()
}

fn icon_font() -> &'static str {
    // Windows 11 has Segoe Fluent Icons; Windows 10 has the same glyphs in Segoe MDL2 Assets
    if std::path::Path::new(r"C:\Windows\Fonts\SegoeIcons.ttf").exists() { "Segoe Fluent Icons" } else { "Segoe MDL2 Assets" }
}

pub fn render(items: &[TextItem], w: u32, h: u32) -> Vec<u8> {
    let mut out = vec![0u8; (w * h * 4) as usize];
    if w == 0 || h == 0 {
        return out;
    }
    unsafe {
        let hdc = CreateCompatibleDC(None);
        let mut bmi = BITMAPINFO::default();
        bmi.bmiHeader.biSize = std::mem::size_of::<BITMAPINFOHEADER>() as u32;
        bmi.bmiHeader.biWidth = w as i32;
        bmi.bmiHeader.biHeight = -(h as i32);
        bmi.bmiHeader.biPlanes = 1;
        bmi.bmiHeader.biBitCount = 32;
        bmi.bmiHeader.biCompression = BI_RGB.0;
        let mut bits = std::ptr::null_mut();
        let Ok(dib) = CreateDIBSection(Some(hdc), &bmi, DIB_RGB_COLORS, &mut bits, None, 0) else {
            let _ = DeleteDC(hdc);
            return out;
        };
        let old = SelectObject(hdc, dib.into());
        SetBkMode(hdc, TRANSPARENT);
        SetTextColor(hdc, COLORREF(0x00FF_FFFF));
        let px = std::slice::from_raw_parts_mut(bits as *mut u8, (w * h * 4) as usize);
        let icon_face = wide(icon_font());
        let ui_face = wide("Segoe UI");
        let bold_face = wide("Segoe UI Semibold");
        for ch in 0..4 {
            if !items.iter().any(|i| i.channel == ch) {
                continue;
            }
            px.fill(0);
            for it in items.iter().filter(|i| i.channel == ch) {
                let face = if it.icon { &icon_face } else if it.bold { &bold_face } else { &ui_face };
                let font = CreateFontW(
                    -(it.size.round() as i32), 0, 0, 0, if it.bold { 600 } else { 400 }, 0, 0, 0,
                    DEFAULT_CHARSET, OUT_DEFAULT_PRECIS, CLIP_DEFAULT_PRECIS, ANTIALIASED_QUALITY, 0, PCWSTR(face.as_ptr()),
                );
                let prev = SelectObject(hdc, font.into());
                let mut rc = RECT { left: it.rect[0], top: it.rect[1], right: it.rect[0] + it.rect[2], bottom: it.rect[1] + it.rect[3] };
                let mut txt: Vec<u16> = it.text.encode_utf16().collect();
                let align = match it.align {
                    Align::Left => DT_LEFT,
                    Align::Center => DT_CENTER,
                    Align::Right => DT_RIGHT,
                };
                DrawTextW(hdc, &mut txt, &mut rc, DT_SINGLELINE | DT_VCENTER | DT_NOPREFIX | DT_END_ELLIPSIS | align);
                SelectObject(hdc, prev);
                let _ = DeleteObject(font.into());
            }
            let _ = GdiFlush();
            for i in 0..(w * h) as usize {
                out[i * 4 + ch] = px[i * 4 + 1];
            }
        }
        SelectObject(hdc, old);
        let _ = DeleteObject(dib.into());
        let _ = DeleteDC(hdc);
    }
    out
}

/// Width of a string in px (for sizing pills to their text).
pub fn measure(text: &str, size: f32, bold: bool) -> f32 {
    unsafe {
        let hdc = CreateCompatibleDC(None);
        let face = wide(if bold { "Segoe UI Semibold" } else { "Segoe UI" });
        let font = CreateFontW(-(size.round() as i32), 0, 0, 0, if bold { 600 } else { 400 }, 0, 0, 0, DEFAULT_CHARSET, OUT_DEFAULT_PRECIS, CLIP_DEFAULT_PRECIS, ANTIALIASED_QUALITY, 0, PCWSTR(face.as_ptr()));
        let prev = SelectObject(hdc, font.into());
        let mut rc = RECT::default();
        let mut txt: Vec<u16> = text.encode_utf16().collect();
        DrawTextW(hdc, &mut txt, &mut rc, DT_SINGLELINE | DT_CALCRECT | DT_NOPREFIX);
        SelectObject(hdc, prev);
        let _ = DeleteObject(font.into());
        let _ = DeleteDC(hdc);
        (rc.right - rc.left) as f32
    }
}
