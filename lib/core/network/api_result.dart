/// Resultado de una llamada al API que puede fallar con un mensaje.
///
/// Reemplaza el patrón "devolver bool y tragarse el error": ahora quien
/// llama sabe SI falló y POR QUÉ. El mensaje viene del servidor cuando
/// existe (p.ej. reglas de negocio como "ya hay partidos jugados").
class ApiResult {
  final bool success;
  final String? message;

  const ApiResult.ok([this.message]) : success = true;
  const ApiResult.fail(this.message) : success = false;
}