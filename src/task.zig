pub usingnamespace @import("index.zig");

var boot_task = Task{ .tid = 0, .esp = 0x47 };
const ListOfTasks = std.TailQueue(*Task);
var first_task = ListOfTasks.Node.init(&boot_task);
var current_task = &first_task;
var tasks = ListOfTasks{
    .first = &first_task,
    .last = &first_task,
    .len = 1,
};

const STACK_SIZE = x86.PAGE_SIZE; // Size of thread stacks.
var tid_counter: u16 = 1;

///ASM
extern fn switch_tasks(new_esp: u32, old_esp_addr: u32) void;

pub const Task = packed struct {
    esp: usize,
    tid: u16,
    //context: isr.Context,
    //cr3: usize,

    pub fn create(entrypoint: usize) !*Task {
        // Allocate and initialize the thread structure.
        var t = try vmem.create(Task);

        t.tid = tid_counter;
        tid_counter +%= 1;
        assert(tid_counter != 0); //overflow

        // allocate a new stack
        t.esp = (try vmem.malloc(STACK_SIZE)) + STACK_SIZE;
        // top of stack is the address that ret will pop
        t.esp -= 4;
        @intToPtr(*usize, t.esp).* = entrypoint;
        // top of stack is ebp that we will pop
        t.esp -= 4;
        @intToPtr(*usize, t.esp).* = t.esp + 8;

        return t;
    }

    pub fn destroy(self: *Task) void {
        vmem.free(self.esp);
        vmem.free(@ptrToInt(self));
    }
};

pub fn new(entrypoint: usize) !void {
    // println("currently: {}", current_task.data.tid);
    // println("first: {}", tasks.first.?.data.tid);
    // println("last: {}", tasks.last.?.data.tid);
    const node = try vmem.create(ListOfTasks.Node);
    node.data = try Task.create(entrypoint);
    tasks.append(node);
    // println("currently: {}", current_task.data.tid);
    // println("first: {}", tasks.first.?.data.tid);
    // println("last: {}", tasks.last.?.data.tid);
}

pub fn switch_to(new_task: *ListOfTasks.Node) void {
    assert(new_task.data != current_task.data);
    // save old stack
    const old_task_esp_addr = &current_task.data.esp;
    current_task = new_task;
    // x86.cli();
    // don't inline the asm function, it needs to ret
    @noInlineCall(switch_tasks, new_task.data.esp, @ptrToInt(old_task_esp_addr));
    // x86.sti();
}

pub fn schedule() void {
    // println("currently: {}", current_task.data.tid);
    // println("first: {}", tasks.first.?.data.tid);
    // println("last: {}", tasks.last.?.data.tid);
    if (current_task.next) |next| {
        // println("switching to {}", next.data.tid);
        switch_to(next);
    } else if (tasks.first) |head| {
        // println("switching to {}", head.data.tid);
        if (head.data != current_task.data) switch_to(head);
    } else {
        introspect();
    }
    // if (current_task.data.tid == 0) switch_to(tasks.last.?.*);
    // if (current_task.data.tid == 1) switch_to(tasks.first.?.*);
    // if (current_task.tid == 2) tasks[0].?.switch_to();
}

pub fn introspect() void {
    var it = tasks.first;
    println("{} tasks", tasks.len);
    while (it) |node| : (it = node.next) {
        if (node.data != current_task.data) println("{}", node.data);
        if (node.data == current_task.data) println("*{}", node.data);
    }
}

// fn initContext(entry_point: usize, stack: usize) isr.Context {
//     // Insert a trap return address to destroy the thread on return.
//     var stack_top = @intToPtr(*usize, stack + STACK_SIZE - @sizeOf(usize));
//     stack_top.* = layout.THREAD_DESTROY;

//     return isr.Context{
//         .cs = gdt.USER_CODE | gdt.USER_RPL,
//         .ss = gdt.USER_DATA | gdt.USER_RPL,
//         .eip = entry_point,
//         .esp = @ptrToInt(stack_top),
//         .eflags = 0x202,

//         .registers = isr.Registers.init(),
//         .interrupt_n = 0,
//         .error_code = 0,
//     };
// }
