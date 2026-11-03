import os
import sys
import time
import ctypes
from ctypes import wintypes
import subprocess
import uvicorn

# 确保在项目根目录
ROOT_DIR = os.path.dirname(os.path.abspath(__file__))
os.chdir(ROOT_DIR)

# FRP 路径
FRP_EXE = r"c:\Users\Administrator\Desktop\pyyyyyy\infrastructure\frp\frpc.exe"
FRP_CFG = r"c:\Users\Administrator\Desktop\pyyyyyy\infrastructure\frp\frpc.toml"

def kill_port_and_frpc():
    """清理残留的 15926 端口和 frpc 进程"""
    try:
        # 清理占用 15926 端口的进程
        cmd = 'for /f "tokens=5" %a in (\'netstat -aon ^| findstr ":15926 " ^| findstr "LISTENING"\') do taskkill /f /pid %a >nul 2>&1'
        subprocess.run(cmd, shell=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        # 清理 frpc
        subprocess.run('taskkill /f /im frpc.exe >nul 2>&1', shell=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    except Exception:
        pass

def setup_job_object():
    """创建 Windows Job Object，绑定子进程生命周期：主进程关闭时内核自动杀死子进程"""
    kernel32 = ctypes.WinDLL('kernel32', use_last_error=True)
    JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE = 0x2000
    JobObjectExtendedLimitInformation = 9

    class IO_COUNTERS(ctypes.Structure):
        _fields_ = [
            ('ReadOperationCount', ctypes.c_uint64),
            ('WriteOperationCount', ctypes.c_uint64),
            ('OtherOperationCount', ctypes.c_uint64),
            ('ReadTransferCount', ctypes.c_uint64),
            ('WriteTransferCount', ctypes.c_uint64),
            ('OtherTransferCount', ctypes.c_uint64),
        ]

    class JOBOBJECT_BASIC_LIMIT_INFORMATION(ctypes.Structure):
        _fields_ = [
            ('PerProcessUserTimeLimit', ctypes.c_int64),
            ('PerJobUserTimeLimit', ctypes.c_int64),
            ('LimitFlags', wintypes.DWORD),
            ('MinimumWorkingSetSize', ctypes.c_size_t),
            ('MaximumWorkingSetSize', ctypes.c_size_t),
            ('ActiveProcessLimit', wintypes.DWORD),
            ('Affinity', ctypes.c_size_t),
            ('PriorityClass', wintypes.DWORD),
            ('SchedulingClass', wintypes.DWORD),
        ]

    class JOBOBJECT_EXTENDED_LIMIT_INFORMATION(ctypes.Structure):
        _fields_ = [
            ('BasicLimitInformation', JOBOBJECT_BASIC_LIMIT_INFORMATION),
            ('IoInfo', IO_COUNTERS),
            ('ProcessMemoryLimit', ctypes.c_size_t),
            ('JobMemoryLimit', ctypes.c_size_t),
            ('PeakProcessMemoryLimit', ctypes.c_size_t),
            ('PeakJobMemoryLimit', ctypes.c_size_t),
        ]

    job = kernel32.CreateJobObjectW(None, None)
    info = JOBOBJECT_EXTENDED_LIMIT_INFORMATION()
    info.BasicLimitInformation.LimitFlags = JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE
    kernel32.SetInformationJobObject(
        job,
        JobObjectExtendedLimitInformation,
        ctypes.byref(info),
        ctypes.sizeof(info)
    )
    return kernel32, job

def main():
    print("=" * 60)
    print("  异动做空雷达 (Fade the Pump) 服务引擎启动中...")
    print("=" * 60)

    # 1. 清理旧进程
    kill_port_and_frpc()
    time.sleep(0.5)

    # 2. 创建 Job Object
    kernel32, job = setup_job_object()

    # 3. 启动 FRP 客户端作为 Job Object 子进程
    frp_proc = None
    if os.path.exists(FRP_EXE) and os.path.exists(FRP_CFG):
        try:
            frp_proc = subprocess.Popen(
                [FRP_EXE, "-c", FRP_CFG],
                stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL,
                creationflags=subprocess.CREATE_NO_WINDOW
            )
            # 绑定到 Job Object，确保关闭此控制台时 frpc.exe 被 Windows 内核强制终止
            kernel32.AssignProcessToJobObject(job, int(frp_proc._handle))
            print("  [OK] FRP 公网隧道已启动 (穿透至 47.92.99.47:15926)")
        except Exception as e:
            print(f"  [WARN] 启动 FRP 失败: {e}")
    else:
        print("  [WARN] 未找到 FRP 客户端路径，仅启动本地服务")

    print(f"  [OK] 本地服务地址: http://127.0.0.1:15926")
    print(f"  [OK] 远程公网地址: http://47.92.99.47:15926")
    print("-" * 60)
    print("  [提示] 保持此窗口开启即可正常使用服务。")
    print("  [退出] 直接点击右上角 [X] 关闭此窗口，服务与穿透将自动完全关闭。")
    print("=" * 60)
    print()

    # 4. 运行 Uvicorn 服务（前台运行，接管控制台，开启热重载）
    try:
        uvicorn.run("server.main:app", host="0.0.0.0", port=15926, reload=True, log_level="info")
    except (KeyboardInterrupt, SystemExit):
        pass
    finally:
        print("\n正在停止服务...")
        if frp_proc:
            try:
                frp_proc.terminate()
            except Exception:
                pass
        kill_port_and_frpc()
        print("服务已完全停止。")

if __name__ == "__main__":
    main()
