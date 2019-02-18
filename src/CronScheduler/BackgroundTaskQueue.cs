using System;
using System.Collections.Concurrent;
using System.Threading;
using System.Threading.Tasks;

namespace CronScheduler.AspNetCore
{
    public class BackgroundTaskQueue : IBackgroundTaskQueue
    {
        private readonly ConcurrentQueue<(Func<CancellationToken, Task>, string, Action<Exception>)>
                    _workItems = new ConcurrentQueue<(Func<CancellationToken, Task>, string, Action<Exception>)>();

        private readonly SemaphoreSlim _signal = new SemaphoreSlim(0);

        public async Task<(Func<CancellationToken, Task>, string, Action<Exception>)> DequeueAsync(CancellationToken cancellationToken)
        {
            await _signal.WaitAsync(cancellationToken);
            _workItems.TryDequeue(out var workItem);

            return workItem;
        }

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
