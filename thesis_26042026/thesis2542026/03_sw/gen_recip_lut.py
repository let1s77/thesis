vals=[]
for x in range(256):
    v = 65535 if x == 0 else min(65535, 65536 // x)
    vals.append(v)
for i in range(0, 256, 8):
    row = ", ".join([f"16'd{v}" for v in vals[i:i+8]])
    print(row)
