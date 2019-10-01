using System.Threading;

namespace CronScheduler.Extensions.BackgroundTask
{
    public class BackgroundTaskContext
    {
        private int _outstandingTaskCount = 0;

        public bool IsComplete => _outstandingTaskCount == 0;

        public int Count => _outstandingTaskCount;

        public void RegisterTask()
        {
            Interlocked.Increment(ref _outstandingTaskCount);
        }

        public void MarkAsComplete()
        {
            Interlocked.Decrement(ref _outstandingTaskCount);
        }
    }
}
