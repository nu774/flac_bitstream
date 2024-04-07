from libc.stdint cimport *
from cython.operator cimport dereference
from cpython cimport *
from cpython.memoryview cimport *

ctypedef int FLAC__bool

cdef extern from "private/bitreader.h":
    ctypedef struct FLAC__BitReader:
        pass
    
    ctypedef FLAC__bool (*FLAC__BitReaderReadCallback)(uint8_t*, size_t*, void*)

    FLAC__BitReader *FLAC__bitreader_new()
    void FLAC__bitreader_delete(FLAC__BitReader*)
    FLAC__bool FLAC__bitreader_init(FLAC__BitReader*, FLAC__BitReaderReadCallback, void*)
    void FLAC__bitreader_free(FLAC__BitReader*)
    FLAC__bool FLAC__bitreader_clear(FLAC__BitReader*)
    
    FLAC__bool FLAC__bitreader_is_consumed_byte_aligned(FLAC__BitReader*)
    uint32_t FLAC__bitreader_bits_left_for_byte_alignment(FLAC__BitReader*)
    uint32_t FLAC__bitreader_get_input_bits_unconsumed(FLAC__BitReader*)
    void FLAC__bitreader_set_limit(FLAC__BitReader*, uint32_t)
    void FLAC__bitreader_remove_limit(FLAC__BitReader*)
    uint32_t FLAC__bitreader_limit_remaining(FLAC__BitReader*)
    void FLAC__bitreader_limit_invalidate(FLAC__BitReader*)

    FLAC__bool FLAC__bitreader_read_raw_uint32(FLAC__BitReader*, uint32_t*, uint32_t)
    FLAC__bool FLAC__bitreader_read_raw_uint64(FLAC__BitReader*, uint64_t*, uint32_t)
    FLAC__bool FLAC__bitreader_skip_bits_no_crc(FLAC__BitReader*, uint32_t)
    FLAC__bool FLAC__bitreader_skip_byte_block_aligned_no_crc(FLAC__BitReader*, uint32_t)
    FLAC__bool FLAC__bitreader_read_byte_block_aligned_no_crc(FLAC__BitReader*, uint8_t*, uint32_t)

cdef extern from "private/bitwriter.h":
    ctypedef struct FLAC__BitWriter:
        pass
    
    FLAC__BitWriter *FLAC__bitwriter_new()
    void FLAC__bitwriter_delete(FLAC__BitWriter*)
    FLAC__bool FLAC__bitwriter_init(FLAC__BitWriter*)
    void FLAC__bitwriter_free(FLAC__BitWriter*)
    void FLAC__bitwriter_clear(FLAC__BitWriter*)

    FLAC__bool FLAC__bitwriter_is_byte_aligned(const FLAC__BitWriter*)
    uint32_t FLAC__bitwriter_get_input_bits_unconsumed(const FLAC__BitWriter*)

    FLAC__bool FLAC__bitwriter_get_buffer(FLAC__BitWriter*, const uint8_t **, size_t *)
    void FLAC__bitwriter_release_buffer(FLAC__BitWriter*)

    FLAC__bool FLAC__bitwriter_write_zeroes(FLAC__BitWriter*, uint32_t)
    FLAC__bool FLAC__bitwriter_write_raw_uint32(FLAC__BitWriter*, uint32_t, uint32_t)
    FLAC__bool FLAC__bitwriter_write_raw_uint64(FLAC__BitWriter*, uint64_t, uint32_t)
    FLAC__bool FLAC__bitwriter_write_byte_block(FLAC__BitWriter*, const uint8_t*, uint32_t)
    FLAC__bool FLAC__bitwriter_zero_pad_to_byte_boundary(FLAC__BitWriter*)



cdef FLAC__bool bitreader_read_callback(uint8_t *buffer, size_t *bytes, void *client_data) noexcept:
    cdef memoryview mv = PyMemoryView_FromMemory(<char*>buffer, bytes[0], PyBUF_WRITE)
    cdef object res = (<object>client_data)(mv)
    if not res: return 0
    bytes[0] = <int>res
    return 1

cdef class CallbackForMemory:
    cdef const uint8_t[:] data
    cdef int off

    def __cinit__(self, const uint8_t[:] data):
        self.data = data
        self.off = 0

    def __call__(self, uint8_t[:] buffer):
        cdef int length = min(len(buffer), len(self.data) - self.off)
        if length == 0:
            return None
        buffer[:length] = self.data[self.off:self.off + length]
        self.off += length
        return length

cdef class BitReader:
    cdef FLAC__BitReader *br
    cdef object read_callback

    def __cinit__(self, object read_callback_or_memory):
        if callable(read_callback_or_memory):
            self.read_callback = read_callback_or_memory
        else:
            self.read_callback = CallbackForMemory(read_callback_or_memory)

        self.br = FLAC__bitreader_new()
        FLAC__bitreader_init(self.br, bitreader_read_callback, <void*>(self.read_callback))
    
    def __dealloc__(self):
        if self.br:
            FLAC__bitreader_delete(self.br)
        self.br = NULL
    
    cpdef void clear(self):
        FLAC__bitreader_clear(self.br)
    
    cpdef bint is_consumed_byte_aligned(self):
        return FLAC__bitreader_is_consumed_byte_aligned(self.br)
    
    cpdef uint32_t bits_left_for_byte_alignment(self):
        return FLAC__bitreader_bits_left_for_byte_alignment(self.br)
    
    cpdef uint32_t get_input_bits_unconsumed(self):
        return FLAC__bitreader_get_input_bits_unconsumed(self.br)

    cpdef void set_limit(self, uint32_t limit):
        FLAC__bitreader_set_limit(self.br, limit)
    
    cpdef uint32_t limit_remaining(self):
        return FLAC__bitreader_limit_remaining(self.br)
    
    cpdef void limit_invalidate(self):
        FLAC__bitreader_limit_invalidate(self.br)
    
    cpdef uint32_t _read_raw_uint32(self, int bits):
        cdef uint32_t value
        if not FLAC__bitreader_read_raw_uint32(self.br, &value, bits):
            raise EOFError
        return value
        
    cpdef uint64_t _read_raw_uint64(self, int bits):
        cdef uint64_t value
        if not FLAC__bitreader_read_raw_uint64(self.br, &value, bits):
            raise EOFError
        return value
    
    cpdef int read_bits(self, int bits):
        if bits <= 32:
            return self._read_raw_uint32(bits)
        else:
            return self._read_raw_uint64(bits)

    cpdef skip_bits(self, int bits):
        if not FLAC__bitreader_skip_bits_no_crc(self.br, bits):
            raise EOFError

    cpdef skip_byte_block(self, int n):
        if not FLAC__bitreader_skip_byte_block_aligned_no_crc(self.br, n):
            raise EOFError

    cpdef read_byte_block(self, uint8_t[:] buffer):
        if not FLAC__bitreader_read_byte_block_aligned_no_crc(self.br, &buffer[0], len(buffer)):
            raise EOFError

cdef class BitWriter:
    cdef FLAC__BitWriter *bw

    def __cinit__(self):
        self.bw = FLAC__bitwriter_new()
        FLAC__bitwriter_init(self.bw)
    
    def __dealloc__(self):
        if self.bw:
            FLAC__bitwriter_delete(self.bw)
        self.bw = NULL

    cpdef void clear(self):
        FLAC__bitwriter_clear(self.bw)

    cpdef bint is_byte_aligned(self):
        return FLAC__bitwriter_is_byte_aligned(self.bw)
    
    cpdef uint32_t get_input_bits_unconsumed(self):
        return FLAC__bitwriter_get_input_bits_unconsumed(self.bw)

    cpdef write_zeroes(self, int bits):
        if not FLAC__bitwriter_write_zeroes(self.bw, bits):
            raise MemoryError

    cpdef write_bits(self, uint64_t val, int bits):
        if not FLAC__bitwriter_write_raw_uint64(self.bw, val, bits):
            raise MemoryError

    cpdef write_byte_block(self, const uint8_t[:] data):
        if not FLAC__bitwriter_write_byte_block(self.bw, &data[0], len(data)):        
            raise MemoryError
    
    cpdef zero_pad_to_byte_boundary(self):
        if not FLAC__bitwriter_zero_pad_to_byte_boundary(self.bw):
            raise MemoryError
    
    cpdef const uint8_t[:] get_buffer(self):
        cdef const uint8_t *ptr
        cdef size_t size
        if not FLAC__bitwriter_get_buffer(self.bw, &ptr, &size):
            if not self.is_byte_aligned():
                raise Exception("get_buffer() requires buffer byte aligned")
            else:
                raise MemoryError
        return PyMemoryView_FromMemory(<char*>ptr, size, PyBUF_READ)
        
    cpdef release_buffer(self):
        FLAC__bitwriter_release_buffer(self.bw)
