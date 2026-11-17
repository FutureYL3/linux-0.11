!
!	setup.s		(C) 1991 Linus Torvalds
!
! setup.s is responsible for getting the system data from the BIOS,
! and putting them into the appropriate places in system memory.
! both setup.s and system has been loaded by the bootblock.
!
! This code asks the bios for memory/disk/other parameters, and
! puts them in a "safe" place: 0x90000-0x901FF, ie where the
! boot-block used to be. It is then up to the protected mode
! system to read them from there before the area is overwritten
! for buffer-blocks.
!

! NOTE! These had better be the same as in bootsect.s!

INITSEG  = 0x9000	! we move boot here - out of the way
SYSSEG   = 0x1000	! system loaded at 0x10000 (65536).
SETUPSEG = 0x9020	! this is the current segment

.globl begtext, begdata, begbss, endtext, enddata, endbss
.text
begtext:
.data
begdata:
.bss
begbss:
.text

entry start
start:
! =========== 此处开始从主板上的属于 bios 的一个内存存储芯片里读机器系统数据 ==============
! ok, the read went well so we get current cursor position and save it for
! posterity.

	mov	ax,#INITSEG	! this is done in bootsect already, but...
	mov	ds,ax
	mov	ah,#0x03	! read cursor pos
	xor	bh,bh
	int	0x10		! save it in known place, con_init fetches
	mov	[0],dx		! it from 0x90000.

! Get memory size (extended mem, kB)

	mov	ah,#0x88
	int	0x15
	mov	[2],ax

! Get video-card data:

	mov	ah,#0x0f
	int	0x10
	mov	[4],bx		! bh = display page
	mov	[6],ax		! al = video mode, ah = window width

! check for EGA/VGA and some config parameters

	mov	ah,#0x12
	mov	bl,#0x10
	int	0x10
	mov	[8],ax
	mov	[10],bx
	mov	[12],cx

! Get hd0 data

	mov	ax,#0x0000
	mov	ds,ax
	lds	si,[4*0x41]
	mov	ax,#INITSEG
	mov	es,ax
	mov	di,#0x0080
	mov	cx,#0x10
	rep
	movsb

! Get hd1 data

	mov	ax,#0x0000
	mov	ds,ax
	lds	si,[4*0x46]
	mov	ax,#INITSEG
	mov	es,ax
	mov	di,#0x0090
	mov	cx,#0x10
	rep
	movsb

! Check that there IS a hd1 :-)

	mov	ax,#0x01500
	mov	dl,#0x81
	int	0x13
	jc	no_disk1
	cmp	ah,#3
	je	is_disk1
no_disk1:
	mov	ax,#INITSEG
	mov	es,ax
	mov	di,#0x0090
	mov	cx,#0x10
	mov	ax,#0x00
	rep
	stosb
is_disk1:

! =========== 此处结束从主板上的属于 bios 的一个内存存储芯片里读机器系统数据 ==============

! now we want to move to protected mode ...从实模式转移到保护模式
	! cli - clear interrupt：关中断
	cli			! no interrupts allowed !

! first we move the system to it's rightful place
! 实模式低地址原来放着中断向量表，所以 bootsect 只能先把内核放在 0x10000。中断已经关掉、马上要离开实模式，这块内存可以覆盖了。

	mov	ax,#0x0000
	cld			! 'direction'=0, movs moves forward
do_move:
	! 0x10000–0x8FFFF 搬到 0x00000–0x7FFFF
	mov	es,ax		! destination segment
	add	ax,#0x1000
	cmp	ax,#0x9000 ! AX 加到 0x9000 就停止，0x90000 处的 BIOS 参数和正在执行的 setup 保持不动。
	jz	end_move
	mov	ds,ax		! source segment
	sub	di,di
	sub	si,si
	mov 	cx,#0x8000
	rep
	movsw
	jmp	do_move

! then we load the segment descriptors

end_move:
	mov	ax,#SETUPSEG	! right, forgot this at first. didn't work :-)
	mov	ds,ax
	lidt	idt_48		! load idt with 0,0
	lgdt	gdt_48		! load gdt with whatever appropriate

! that was painless, now we enable A20
!
! 打开 A20。8086 只有 A0–A19，超过 1 MB 时这一位会丢掉，部分旧程序
! 依赖这种回绕。80286 以后只给 A20 加了门：门关上时该位被强制为 0，0x100000 与
! 0x000000 重合。A21–A31 没有这种门，直接连到地址总线，不用再打开
!
! 门由键盘控制器 8042 的输出端口第 1 位控制。0x64 是命令口，0x60 是数据口。
! empty_8042 读 0x64，等到输入缓冲为空才能写。0xD1 表示下一字节写入输出端口；
! 0xDF 的第 1 位为 1，打开放行 A20，第 0 位为 1，避免把 CPU 复位

	call	empty_8042
	mov	al,#0xD1		! command write
	out	#0x64,al
	call	empty_8042
	mov	al,#0xDF		! A20 on
	out	#0x60,al
	call	empty_8042

! well, that went ok, I hope. Now we have to reprogram the interrupts :-(
! we put them right after the intel-reserved hardware interrupts, at
! int 0x20-0x2F. There they won't mess up anything. Sadly IBM really
! messed this up with the original PC, and they haven't been able to
! rectify it afterwards. Thus the bios puts interrupts at 0x08-0x0f,
! which is used for the internal hardware interrupts as well. We just
! have to reprogram the 8259's, and it isn't fun.

	mov	al,#0x11		! initialization sequence
	out	#0x20,al		! send it to 8259A-1
	.word	0x00eb,0x00eb		! jmp $+2, jmp $+2
	out	#0xA0,al		! and to 8259A-2
	.word	0x00eb,0x00eb
	mov	al,#0x20		! start of hardware int's (0x20)
	out	#0x21,al
	.word	0x00eb,0x00eb
	mov	al,#0x28		! start of hardware int's 2 (0x28)
	out	#0xA1,al
	.word	0x00eb,0x00eb
	mov	al,#0x04		! 8259-1 is master
	out	#0x21,al
	.word	0x00eb,0x00eb
	mov	al,#0x02		! 8259-2 is slave
	out	#0xA1,al
	.word	0x00eb,0x00eb
	mov	al,#0x01		! 8086 mode for both
	out	#0x21,al
	.word	0x00eb,0x00eb
	out	#0xA1,al
	.word	0x00eb,0x00eb
	mov	al,#0xFF		! mask off all interrupts for now
	out	#0x21,al
	.word	0x00eb,0x00eb
	out	#0xA1,al

! well, that certainly wasn't fun :-(. Hopefully it works, and we don't
! need no steenking BIOS anyway (except for the initial loading :-).
! The BIOS-routine wants lots of unnecessary data, and it's less
! "interesting" anyway. This is how REAL programmers do it.
!
! Well, now's the time to actually move into protected mode. To make
! things as simple as possible, we do no register set-up or anything,
! we let the gnu-compiled 32-bit programs do that. We just jump to
! absolute address 0x00000, in 32-bit protected mode.

	mov	ax,#0x0001	! protected mode (PE) bit
	lmsw	ax		! This is it!
	jmpi	0,8		! jmp offset 0 of segment 8 (cs)

! This routine checks that the keyboard command queue is empty
! No timeout is used - if this hangs there is something wrong with
! the machine, and we probably couldn't proceed anyway.
empty_8042:
	.word	0x00eb,0x00eb
	in	al,#0x64	! 8042 status port
	test	al,#2		! is input buffer full?
	jnz	empty_8042	! yes - loop
	ret

! GDT 表项的格式：
! 字节	 		     	 字段
! 0–1				段界限的低 16 位
! 2–4				段基址的低 24 位
! 5					访问权限
! 6 的低 4 位		 段界限的高 4 位
! 6 的高 4 位		 G、D/B、L、AVL
! 7					段基址的高 8 位

gdt:
	! ，GDT 表第一项，空项
	.word	0,0,0,0		! dummy

	! ，GDT 表第二项，内核代码段描述符
	.word	0x07FF		! 8Mb - limit=2047 (2048*4096=8Mb)
	.word	0x0000		! base address=0
	.word	0x9A00		! code read/exec
	.word	0x00C0		! granularity=4096, 386

	! ，GDT 表第三项，内核数据段描述符
	.word	0x07FF		! 8Mb - limit=2047 (2048*4096=8Mb)
	.word	0x0000		! base address=0
	.word	0x9200		! data read/write
	.word	0x00C0		! granularity=4096, 386

! idtr 和 gdtr 是 Intel 80386 的寄存器，用于存储 IDT 和 GDT 的基址和界限，都是 48 位寄存器。
! idtr 和 gdtr 的格式是：
	! 字节 0-1：界限，即每张表的最大内存字节数，实际项数为界限/8（即 IDT 表和 GDT 表每项占 8 字节）
	! 字节 2-5：基址，即每张表的起始物理地址

! idt_48 的基址和界限都是 0，
! IDTR 因此指向地址 0，表面这张表没有可用项。真正的 IDT 要到 head.s 里再建立，并重新执行 lidt
idt_48:
	.word	0			! idt limit=0
	.word	0,0			! idt base=0L

! gdt_48 的基址指向标签 gdt 所在的物理地址
! 界限是 2048 (0x800)，表示 256 个 GDT 项，即 256 * 8 = 2048 字节
gdt_48:
	.word	0x800		! gdt limit=2048, 256 GDT entries
	.word	512+gdt,0x9	! gdt base = 0X9xxxx
	
.text
endtext:
.data
enddata:
.bss
endbss:
