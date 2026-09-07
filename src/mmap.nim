## nimorphy/mmap.nim
## Кроссплатформенная поддержка memory-mapped files (mmap)

when defined(windows):
  type
    Handle = int

  const
    GENERIC_READ = 0x80000000'i32
    FILE_SHARE_READ = 1'i32
    OPEN_EXISTING = 3'i32
    FILE_ATTRIBUTE_NORMAL = 0x80'i32
    PAGE_READONLY = 0x02'i32
    FILE_MAP_READ = 0x04'i32
    INVALID_HANDLE_VALUE = -1

  proc createFileW(
    lpFileName: WideCString,
    dwDesiredAccess: int32,
    dwShareMode: int32,
    lpSecurityAttributes: pointer,
    dwCreationDisposition: int32,
    dwFlagsAndAttributes: int32,
    hTemplateFile: Handle
  ): Handle {.stdcall, dynlib: "kernel32", importc: "CreateFileW".}

  proc closeHandle(hObject: Handle): int32 {.stdcall, dynlib: "kernel32", importc: "CloseHandle".}

  proc getFileSize(hFile: Handle, lpFileSizeHigh: ptr int32): int32 {.stdcall, dynlib: "kernel32", importc: "GetFileSize".}

  proc createFileMappingW(
    hFile: Handle,
    lpFileMappingAttributes: pointer,
    flProtect: int32,
    dwMaximumSizeHigh: int32,
    dwMaximumSizeLow: int32,
    lpName: WideCString
  ): Handle {.stdcall, dynlib: "kernel32", importc: "CreateFileMappingW".}

  proc mapViewOfFile(
    hFileMappingObject: Handle,
    dwDesiredAccess: int32,
    dwFileOffsetHigh: int32,
    dwFileOffsetLow: int32,
    dwNumberOfBytesToMap: int
  ): pointer {.stdcall, dynlib: "kernel32", importc: "MapViewOfFile".}

  proc unmapViewOfFile(lpBaseAddress: pointer): int32 {.stdcall, dynlib: "kernel32", importc: "UnmapViewOfFile".}

  type
    MmapFile* = object
      address*: pointer
      size*: int
      fileHandle: Handle
      mapHandle: Handle

  proc close*(m: var MmapFile) =
    if m.address != nil:
      discard unmapViewOfFile(m.address)
      m.address = nil
    if m.mapHandle != 0 and m.mapHandle != INVALID_HANDLE_VALUE:
      discard closeHandle(m.mapHandle)
      m.mapHandle = 0
    if m.fileHandle != 0 and m.fileHandle != INVALID_HANDLE_VALUE:
      discard closeHandle(m.fileHandle)
      m.fileHandle = 0
    m.size = 0

  proc openMmapFile*(path: string): MmapFile =
    var res: MmapFile
    let fHandle = createFileW(
      newWideCString(path),
      GENERIC_READ,
      FILE_SHARE_READ,
      nil,
      OPEN_EXISTING,
      FILE_ATTRIBUTE_NORMAL,
      0
    )
    if fHandle == INVALID_HANDLE_VALUE:
      raise newException(IOError, "Cannot open file: " & path)
    
    var sizeHigh: int32 = 0
    let sizeLow = getFileSize(fHandle, addr sizeHigh)
    let totalSize = (int(sizeHigh) shl 32) or (int(sizeLow) and 0xFFFFFFFF)
    
    let mHandle = createFileMappingW(fHandle, nil, PAGE_READONLY, 0, 0, nil)
    if mHandle == 0:
      discard closeHandle(fHandle)
      raise newException(IOError, "Cannot create file mapping: " & path)
      
    let view = mapViewOfFile(mHandle, FILE_MAP_READ, 0, 0, 0)
    if view == nil:
      discard closeHandle(mHandle)
      discard closeHandle(fHandle)
      raise newException(IOError, "Cannot map view of file: " & path)

    res.address = view
    res.size = totalSize
    res.fileHandle = fHandle
    res.mapHandle = mHandle
    return res

else:
  import posix

  type
    MmapFile* = object
      address*: pointer
      size*: int
      fd: cint

  proc close*(m: var MmapFile) =
    if m.address != nil and m.address != MAP_FAILED:
      discard munmap(m.address, m.size)
      m.address = nil
    if m.fd >= 0:
      discard posix.close(m.fd)
      m.fd = -1
    m.size = 0

  proc openMmapFile*(path: string): MmapFile =
    var res: MmapFile
    let fd = posix.open(path.cstring, O_RDONLY)
    if fd < 0:
      raise newException(IOError, "Cannot open file: " & path)
      
    var statBuf: Stat
    if fstat(fd, statBuf) < 0:
      discard posix.close(fd)
      raise newException(IOError, "Cannot stat file: " & path)
      
    let size = statBuf.st_size.int
    let addrPtr = mmap(nil, size, PROT_READ, MAP_SHARED, fd, 0)
    if addrPtr == MAP_FAILED:
      discard posix.close(fd)
      raise newException(IOError, "mmap failed for: " & path)
      
    res.address = addrPtr
    res.size = size
    res.fd = fd
    return res