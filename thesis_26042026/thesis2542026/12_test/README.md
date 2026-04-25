# Quartus Terminal + Status Script

Muc tieu: chay Quartus ngay trong terminal va nhan status nhanh (error/warning) qua Python.

## 1) Nap Quartus vao terminal hien tai

```powershell
Set-Location "c:\Users\Ms Khanh\OneDrive - hcmut.edu.vn\Desktop\DATN\works_code_DA2\12_test"
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass -Force
.\quartus_env.ps1
```

Neu muon luu vao User PATH:

```powershell
.\quartus_env.ps1 -Persist
```

## 2) Chay Quartus + sinh log

```powershell
.\run_quartus.ps1 -ProjectDir "..\06_FGPA_Imple\thesis" -Revision "thesis_v1" -Stage map
```

Co the thay `-Stage` bang: `map`, `fit`, `asm`, `sta`, `full`.

Log duoc luu trong:
- `12_test/log/`

## 3) Lay status bang Python

```powershell
python .\quartus_status.py --revision thesis_v1 --report-dir "..\06_FGPA_Imple\thesis\output_files"
```

Theo doi realtime khi Quartus dang chay:

```powershell
python .\quartus_status.py --log .\log\quartus_thesis_v1_map_YYYYMMDD_HHMMSS.log --revision thesis_v1 --report-dir "..\06_FGPA_Imple\thesis\output_files" --watch --interval 2
```

Ghi ra JSON:

```powershell
python .\quartus_status.py --revision thesis_v1 --report-dir "..\06_FGPA_Imple\thesis\output_files" --write-json .\quartus_status.json
```

## Notes
- Script Python parse tong quan error/warning tu command log + `.map.rpt`/`.flow.rpt`.
- `run_quartus.ps1` tu dong goi `quartus_status.py` o cuoi luot chay neu co Python trong PATH.
