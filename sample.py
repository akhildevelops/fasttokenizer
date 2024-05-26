import ctypes
lib = ctypes.CDLL("./zig-out/lib/libfasttokenizer.so")
lib.token_ranker.restype=ctypes.c_void_p
lib.encode.argtypes=(ctypes.c_char_p,ctypes.POINTER(ctypes.c_uint),ctypes.c_void_p)
lib.encode.restype=ctypes.POINTER(ctypes.c_uint)
# Define a Python function that calls the Zig function

def encode(text:bytes):
    token_ranker = lib.token_ranker()
    text = ctypes.c_char_p(text)
    i = ctypes.pointer(ctypes.c_uint())
    result = lib.encode(text,i,token_ranker)
    for i in range(0..i[0]):
        print(result[i])


if __name__=="__main__":
    print(encode(b"Operations on vectors shorter than the target machine's native SIMD size will typically compile to single "))