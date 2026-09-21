using Microsoft.AspNetCore.Mvc;

namespace StatusApi.Controllers;

[ApiController]
[Route("api")]
public class StatusController : ControllerBase
{
    /// <summary>
    /// Endpoint de saúde exigido pelo case. Retorna "Healthy" quando a aplicação está no ar.
    /// </summary>
    [HttpGet("status")]
    public IActionResult GetStatus()
    {
        return Ok("Healthy");
    }
}
