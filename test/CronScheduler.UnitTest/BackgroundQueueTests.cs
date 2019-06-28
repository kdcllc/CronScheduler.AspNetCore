using CronScheduler.AspNetCore;
using System.Threading;
using System.Threading.Tasks;
using Xunit;

namespace CronScheduler.UnitTest
{
    public class BackgroundQueueTests
    {
        [Fact(Skip ="Review")]
        public async Task Dequeue_With_Susseful_WorkItemName()
        {
            var workItemName = "TestItem";
            var context = new BackgroundTaskContext();

            var service = new BackgroundTaskQueue(context);

            service.QueueBackgroundWorkItem(async token =>
            {
                await new TaskCompletionSource<object>().Task;
            }
            , workItemName);

            var task = await service.DequeueAsync(CancellationToken.None);

            await task.workItem(CancellationToken.None);

            Assert.Equal(workItemName, task.workItemName);
        }
    }
}
