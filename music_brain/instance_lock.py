"""Windows byte lock. Never read another instance's locked byte."""
import errno
import msvcrt


def acquire_instance(path):
    handle = path.open('a+b')
    handle.seek(0)
    try:
        # Windows permits locking a region beyond EOF. Reading/initializing the
        # byte first raises PermissionError while another launcher owns it.
        msvcrt.locking(handle.fileno(), msvcrt.LK_NBLCK, 1)
    except OSError as exc:
        handle.close()
        if exc.errno in (errno.EACCES, errno.EAGAIN, errno.EDEADLK):
            return None
        raise
    return handle
