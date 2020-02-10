using System;
using System.Collections.Concurrent;
using System.Threading;
using System.Threading.Tasks;

namespace CronScheduler.Extensions.BackgroundTask
{
    public class BackgroundTaskQueue : IBackgroundTaskQueue, IDisposable
    {
        private readonly ConcurrentQueue<(Func<CancellationToken, Task> workItem, string workItemName, Action<Exception> onExeption)>
                    _workItems = new ConcurrentQueue<(Func<CancellationToken, Task> workItem, string workItemName, Action<Exception> onException)>();

        private readonly SemaphoreSlim _signal = new SemaphoreSlim(0);
        private readonly BackgroundTaskContext _context;

        public BackgroundTaskQueue(BackgroundTaskContext context)
        {
            _context = context;
        }

        /// <inheritdoc/>
        public async Task<(Func<CancellationToken, Task> workItem, string workItemName, Action<Exception> onException)>
            DequeueAsync(CancellationToken cancellationToken)
        {
            await _signal.WaitAsync(cancellationToken);
            _workItems.TryDequeue(out var workItem);
            return workItem;
        }

        public void Dispose()
        {
            Dispose(true);
            GC.SuppressFinalize(this);
        }

        /// <inheritdoc/>
        public void QueueBackgroundWorkItem(
            Func<CancellationToken, Task> workItem,
            string workItemName,
            Action<Exception> onException)
        {
            if (workItem == null)
            {
                throw new ArgumentNullException(nameof(workItem));
            }

            _workItems.Enqueue((workItem, workItemName, onException));
            _signal.Release();
            _context.RegisterTask();
        }

        public void QueueBackgroundWorkItem(Func<CancellationToken, Task> workItem, Action<Exception> onException)
        {
            QueueBackgroundWorkItem(workItem, string.Empty, onException);
        }

        public void QueueBackgroundWorkItem(Func<CancellationToken, Task> workItem, string workItemName = "")
        {
            QueueBackgroundWorkItem(workItem, workItemName, (x) => { });
        }

        protected virtual void Dispose(bool disposing)
        {
            if (disposing)
            {
                _signal?.Dispose();
            }
        }
    }
}
