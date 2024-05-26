import ctypes
lib = ctypes.CDLL("./zig-out/lib/libfasttokenizer.so")
lib.token_ranker.restype=ctypes.POINTER(ctypes.c_int)


def encode(text:bytes):
    token_ranker = lib.token_ranker()


if __name__=="__main__":
    print(encode(b"Operations on vectors shorter than the target machine's native SIMD size will typically compile to single "))