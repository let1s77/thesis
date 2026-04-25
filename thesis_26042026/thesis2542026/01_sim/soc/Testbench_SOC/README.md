# Testbench_SOC

Cau truc mo phong giong Testbench_IPU_SOC:
- script/run_soc_128_fullframe.tcl
- script/run_soc_128_fullframe_47.tcl
- sim/soc_128_tb.sv
- sim/image/
- sim/image_test/
- sim/image_47/
- work/
- transcript

Muc tieu:
- Nap anh BMP input vao IMG_IN BRAM cua SoC.
- Cau hinh IPU qua register interface noi bo cua soc_top (testbench force).
- Chay IPU va xuat 2 anh de so sanh truoc/sau:
  - soc_input_128.bmp
  - soc_output_128.bmp

## Cach chay

Case test:

```
do 01_sim/soc/Testbench_SOC/script/run_soc_128_fullframe.tcl
```

Case anh 47:

```
do 01_sim/soc/Testbench_SOC/script/run_soc_128_fullframe_47.tcl
```

Co the override duong dan:
- IMG_IN: duong dan anh BMP 128x128
- OUT_DIR: thu muc output
