using System;
using System.Collections.Concurrent;
using System.Threading;
using System.Threading.Tasks;

namespace CronScheduler.AspNetCore
{
    public class BackgroundTaskQueue : IBackgroundTaskQueue
    {
        private readonly ConcurrentQueue<(Func<CancellationToken, Task> workItem, string workItemName, Action<Exception> onExeption)>
                    _workItems = new ConcurrentQueue<(Func<CancellationToken, Task> workItem, string workItemName, Action<Exception> onException)>();

        private readonly SemaphoreSlim _signal = new SemaphoreSlim(0);

        /// <inheritdoc/>
        public async Task<(Func<CancellationToken, Task> workItem, string workItemName, Action<Exception> onException)>
            DequeueAsync(CancellationToken cancellationToken)
        {
            await _signal.WaitAsync(cancellationToken);
            _workItems.TryDequeue(out var workItem);

            return workItem;
        }

        /// <inheritdoc/>
        public void QueueBackgroundWorkItem(
            Func<CancellationToken, Task> workItem,
            string workItemName = default,
            Action<Exception> onException= default)
        {
            if (workItem == null)
            {
                throw new ArgumentNullException(nameof(workItem));
            }

            _workItems.Enqueue((workItem,workItemName,onException));
            _signal.Release();
        }
    }
}
