	.text

/* Switch from current_thread to next_thread. Make next_thread
 * the current_thread, and set next_thread to 0.
 * Use eax as a temporary register; it is caller saved.
 */
	.globl thread_switch
thread_switch:
	# 1. Save current thread state into the structure pointed by current_thread
	# pushal/popal: edi, esi, ebp, ebx, edx, ecx, eax
	pushal 						# push registers onto current_thread->stack
	movl current_thread, %eax 	# %eax = &(current_thread->sp)
	movl %esp, (%eax) 			# %esp = *(%eax)

	# 2. restore next_thread's state
	movl next_thread, %eax
	movl (%eax), %esp # %esp = next_thread->sp
	popal # restore registers from next_thread->stack

	# 3. Make current_thread point to where next_thread was pointing to
	movl next_thread, %eax
	movl %eax, current_thread

	# Next call to thread_schedule() would find a new value for next_thread

	ret				/* pop return address from stack */