using System.Threading;

namespace CronScheduler.AspNetCore
{
    public class BackgroundTaskContext
    {
        private int _outstandingTaskCount = 0;

        public void RegisterTask()
        {
            Interlocked.Increment(ref _outstandingTaskCount);
        }

        public void MarkAsComplete()
        {
            Interlocked.Decrement(ref _outstandingTaskCount);
        }

        public bool IsComplete => _outstandingTaskCount == 0;

        public int Count => _outstandingTaskCount;
    }
}
