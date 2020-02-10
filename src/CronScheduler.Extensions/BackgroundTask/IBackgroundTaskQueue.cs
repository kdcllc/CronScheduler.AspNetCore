using System;
using System.Threading;
using System.Threading.Tasks;

namespace CronScheduler.Extensions.BackgroundTask
{
    /// <summary>
    /// Background Task Queue.
    /// </summary>
    public interface IBackgroundTaskQueue
    {
        /// <summary>
        /// Adds Task into the queue.
        /// </summary>
        /// <param name="workItem">The Task item to queue.</param>
        /// <param name="workItemName">The name for the executing task.</param>
        /// <param name="onException">The delegate for exception handling of the task.</param>
        void QueueBackgroundWorkItem(
            Func<CancellationToken, Task> workItem,
            string workItemName,
            Action<Exception> onException);

        void QueueBackgroundWorkItem(Func<CancellationToken, Task> workItem, Action<Exception> onException);

        void QueueBackgroundWorkItem(Func<CancellationToken, Task> workItem, string workItemName = "");

        /// <summary>
        /// <summary>
        /// Dequeues Task from the Queue and adds wait lock from the thread of the <see cref="QueuedHostedService"/> based on the
        /// <see cref="CancellationToken"/>.
        /// </summary>
        /// </summary>
        /// <param name="cancellationToken"></param>
        /// <returns></returns>
        Task<(Func<CancellationToken, Task> workItem, string workItemName, Action<Exception> onException)>
            DequeueAsync(CancellationToken cancellationToken);
    }
}
